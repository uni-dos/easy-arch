### Introduction
[easy-arch](https://github.com/uni-dos/easy-arch) is a **script** that boostrap a basic **Arch Linux** environment with **BTRFS snapshots** by using a fully automated process (UEFI only).
Special thanks to [classy-giraffe](https://github.com/classy-giraffe) for creating this script.

### How does it work?
1. Download an Arch Linux ISO from [here](https://archlinux.org/download/)
2. Flash the ISO onto an [USB Flash Drive](https://wiki.archlinux.org/index.php/USB_flash_installation_medium).
3. Boot the live environment.
4. Set the keyboard layout by using `loadkeys`.
5. Connect to the internet.
6. git clone https://github.com/uni-dos/easy-arch.
7. Type ./easy-arch/easy-arch.sh to run the install script.

### Partitions layout 

| Partition Number | Label     | Size              | Mountpoint     | Filesystem              |
|------------------|-----------|-------------------|----------------|-------------------------|
| 1                | ESP       | 512 MiB           | /boot/efi      | FAT32                   |
| 2                | Root      | Rest of the disk  | /              | BTRFS                   |

### BTRFS subvolumes layout

| Subvolume Number | Subvolume Name | Mountpoint       |
|------------------|----------------|------------------|
| 1                | @              | /                |
| 2                | @home          | /home            |
| 3                | @snapshots     | /.snapshots      |
| 4                | @var           | /var             |
