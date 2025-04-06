

# ssh into the box and format shit:


```bash
root@192.168.1.100's password:
root@ubuntu:~# fdisk -l /dev/nvme0n1
Disk /dev/nvme0n1: 476.94 GiB, 512110190592 bytes, 1000215216 sectors
Disk model: Micron MTFDKCD512TFK
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: 78A9D79C-2762-4501-A8F4-BD25BEDB703C

Device           Start        End   Sectors   Size Type
/dev/nvme0n1p1    2048    2203647   2201600     1G EFI System
/dev/nvme0n1p2 2203648 1000212479 998008832 475.9G Linux filesystem
root@ubuntu:~# fdisk -l /dev/nvme0n1
Disk /dev/nvme0n1: 476.94 GiB, 512110190592 bytes, 1000215216 sectors
Disk model: Micron MTFDKCD512TFK
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: 78A9D79C-2762-4501-A8F4-BD25BEDB703C

Device           Start        End   Sectors   Size Type
/dev/nvme0n1p1    2048    2203647   2201600     1G EFI System
/dev/nvme0n1p2 2203648 1000212479 998008832 475.9G Linux filesystem
root@ubuntu:~# mkfs.fat -F32 /dev/nvme0n1p1
mkfs.fat 4.2 (2021-01-31)
root@ubuntu:~# cryptsetup luksFormat /dev/nvme0n1p2
WARNING: Device /dev/nvme0n1p2 already contains a 'ext4' superblock signature.

WARNING!
========
This will overwrite data on /dev/nvme0n1p2 irrevocably.

Are you sure? (Type 'yes' in capital letters): YES
Enter passphrase for /dev/nvme0n1p2:
Verify passphrase:
root@ubuntu:~# cryptsetup open /dev/nvme0n1p2 root
Enter passphrase for /dev/nvme0n1p2:
No key available with this passphrase.
Enter passphrase for /dev/nvme0n1p2:
root@ubuntu:~# mkfs.ext4 /dev/mapper/root
mke2fs 1.47.2 (1-Jan-2025)
Creating filesystem with 124747008 4k blocks and 31186944 inodes
Filesystem UUID: 2e342bab-ba3e-4b18-ba1e-3c9527d24be8
Superblock backups stored on blocks:
	32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632, 2654208,
	4096000, 7962624, 11239424, 20480000, 23887872, 71663616, 78675968,
	102400000

Allocating group tables: done
Writing inode tables: done
Creating journal (262144 blocks): done
Writing superblocks and filesystem accounting information: done

root@ubuntu:~# mount /dev/mapper/root /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot
root@ubuntu:~# ls /mnt/
boot  lost+found
root@ubuntu:~# mkdir /mnt/etc/nixos
mkdir: cannot create directory '/mnt/etc/nixos': No such file or directory
root@ubuntu:~# mkdir /mnt/etc/nixos -p
root@ubuntu:~# vim /mnt/etc/nixos/flake.nix
root@ubuntu:~# nix --extra-experimental-features 'nix-command flakes' run github:NixOS/nixpkgs/nixos-24.11#nixos-install -- --impure --flake /mnt/etc/nixos#example && systemctl reboot -i
```