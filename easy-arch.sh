#!/usr/bin/env -S bash -e

# Cleaning the TTY.
clear

# Selecting a kernel to install. 
kernel_selector () {
    echo "List of kernels:"
    echo "1) Stable — Vanilla Linux kernel and modules, with a few patches applied."
    echo "2) Hardened — A security-focused Linux kernel."
    echo "3) Longterm — Long-term support (LTS) Linux kernel and modules."
    echo "4) Zen Kernel — Optimized for desktop usage."
    read -r -p "Insert the number of the corresponding kernel: " choice
    echo "$choice will be installed"
    case $choice in
        1 ) kernel=linux
            ;;
        2 ) kernel=linux-hardened
            ;;
        3 ) kernel=linux-lts
            ;;
        4 ) kernel=linux-zen
            ;;
        * ) echo "You did not enter a valid selection."
            kernel_selector
    esac
}

# Selecting a way to handle internet connection. 
network_selector () {
    echo "Network utilities:"
    echo "1) IWD — iNet wireless daemon is a wireless daemon for Linux written by Intel (WiFi-only)."
    echo "2) NetworkManager — Program for providing detection and configuration for systems to automatically connect to networks (both WiFi and Ethernet)."
    echo "3) wpa_supplicant — It's a cross-platform supplicant with support for WEP, WPA and WPA2 (WiFi-only, a DHCP client will be automatically installed too.)"
    echo "4) I will do this on my own."
    read -r -p "Insert the number of the corresponding networking utility: " choice
    echo "$choice will be installed"
    case $choice in
        1 ) echo "Installing IWD."    
            pacstrap /mnt iwd
            echo "Enabling IWD."
            systemctl enable iwd --root=/mnt &>/dev/null
            ;;
        2 ) echo "Installing NetworkManager."
            pacstrap /mnt networkmanager
            echo "Enabling NetworkManager."
            systemctl enable NetworkManager --root=/mnt &>/dev/null
            ;;
        3 ) echo "Installing wpa_supplicant and dhcpcd."
            pacstrap /mnt wpa_supplicant dhcpcd
            echo "Enabling wpa_supplicant and dhcpcd."
            systemctl enable wpa_supplicant --root=/mnt &>/dev/null
            systemctl enable dhcpcd --root=/mnt &>/dev/null
            ;;
        4 )
            ;;
        * ) echo "You did not enter a valid selection."
            network_selector
    esac
}

# Checking the microcode to install.
CPU=$(grep vendor_id /proc/cpuinfo)
if [[ $CPU == *"AuthenticAMD"* ]]
then
    microcode=amd-ucode
else
    microcode=intel-ucode
fi

#ensure the system clock is accurate
timedatectl set-ntp true

# Selecting the target for the installation.
PS3="Select the disk where Arch Linux is going to be installed: "
select ENTRY in $(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd");
do
    DISK=$ENTRY
    echo "Installing Arch Linux on $DISK."
    break
done

# Deleting old partition scheme.
read -r -p "This will delete the current partition table on $DISK. Do you agree [y/N]? " response
response=${response,,}
if [[ "$response" =~ ^(yes|y)$ ]]
then
    wipefs -af "$DISK" &>/dev/null
    sgdisk -Zo "$DISK" &>/dev/null
else
    echo "Quitting."
    exit
fi

# Creating a new partition scheme.
echo "Creating new partition scheme on $DISK."
parted -s "$DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 301MiB \
    set 1 esp on \
    mkpart Root 301MiB 100% \

ESP="/dev/disk/by-partlabel/ESP"
ROOT="/dev/disk/by-partlabel/Root"

# Informing the Kernel of the changes.
echo "Informing the Kernel about the disk changes."
partprobe "$DISK"

# Formatting the ESP as FAT32.
echo "Formatting the EFI Partition as FAT32."
mkfs.fat -F 32 $ESP &>/dev/null

# Formatting ROOT as BTRFS.
echo "Formatting the LUKS container as BTRFS."
mkfs.btrfs $ROOT &>/dev/null
mount $ROOT /mnt

# Creating BTRFS subvolumes.
echo "Creating BTRFS subvolumes."
btrfs su cr /mnt/@ &>/dev/null
btrfs su cr /mnt/@home &>/dev/null
btrfs su cr /mnt/@snapshots &>/dev/null
btrfs su cr /mnt/@var_log &>/dev/null

# Mounting the newly created subvolumes.
umount /mnt
echo "Mounting the newly created subvolumes."
mount -o ssd,noatime,space_cache=v2,compress=zstd,subvol=@ $ROOT /mnt
mkdir -p /mnt/{home,.snapshots,/var/log,/boot/efi}
mount -o ssd,noatime,space_cache=v2,compress=zstd,subvol=@home $ROOT /mnt/home
mount -o ssd,noatime,space_cache=v2,compress=zstd,subvol=@snapshots $ROOT /mnt/.snapshots
mount -o ssd,noatime,space_cache=v2,compress=zstd,subvol=@var_log $ROOT /mnt/var/log
chattr +C /mnt/var/log

# Mounting the boot partition
mount $ESP /mnt/boot/efi

kernel_selector

# Pacstrap (setting up a base sytem onto the new root).
echo "Installing the base system (it may take a while)."
pacstrap /mnt base $kernel $microcode linux-firmware btrfs-progs grub grub-btrfs efibootmgr snapper base-devel snap-pac zram-generator

network_selector

# Generating /etc/fstab.
echo "Generating a new fstab."
genfstab -U /mnt >> /mnt/etc/fstab

# Setting hostname.
read -r -p "Please enter the hostname: " hostname
echo "$hostname" > /mnt/etc/hostname

# Setting up locales.
read -r -p "Please insert the locale you use (format: xx_XX): " locale
echo "$locale.UTF-8 UTF-8"  > /mnt/etc/locale.gen
echo "LANG=$locale.UTF-8" > /mnt/etc/locale.conf

# Setting up keyboard layout.
read -r -p "Please insert the keyboard layout you use: " kblayout
echo "KEYMAP=$kblayout" > /mnt/etc/vconsole.conf

# Setting hosts file.
echo "Setting hosts file."
cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF

# Configuring the system.    
arch-chroot /mnt /bin/bash -e <<EOF
    
    # Setting up timezone.
    ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime &>/dev/null
    
    # Setting up clock.
    hwclock --systohc

    # Generating locales.
    echo "Generating locales."
    locale-gen &>/dev/null

    # Generating a new initramfs.
    echo "Creating a new initramfs."
    mkinitcpio -P &>/dev/null

    # Snapper configuration
    umount /.snapshots
    rm -r /.snapshots
    snapper --no-dbus -c root create-config /
    btrfs subvolume delete /.snapshots &>/dev/null
    mkdir /.snapshots
    mount -a
    chmod 750 /.snapshots

    # Installing GRUB.
    echo "Installing GRUB on /boot/efi."
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB &>/dev/null
    
    # Creating grub config file.
    echo "Creating GRUB config file."
    grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null

EOF

# Setting root password.
echo "Setting root password."
arch-chroot /mnt /bin/passwd

# Enabling Snapper automatic snapshots.
echo "Enabling Snapper and automatic snapshots entries."
systemctl enable snapper-timeline.timer --root=/mnt &>/dev/null
systemctl enable snapper-cleanup.timer --root=/mnt &>/dev/null
systemctl enable grub-btrfs.path --root=/mnt &>/dev/null

# Enabling systemd-oomd.
echo "Enabling systemd-oomd."
systemctl enable systemd-oomd --root=/mnt &>/dev/null

# ZRAM configuration
bash -c 'cat > /mnt/etc/systemd/zram-generator.conf' <<-'EOF'
[zram0]
zram-fraction = 1
max-zram-size = 8192
EOF

# Finishing up
echo "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
exit
