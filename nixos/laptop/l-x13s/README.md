# l-x13s NixOS install

The ThinkPad X13s is `aarch64-linux`. Build and install this host on the X13s
itself, or configure a native ARM builder. Building it on plain `x86_64-linux`
fails while evaluating/building X13s DTBs.

## Known Bootloader Issue

The X13s nixos-hardware PR currently injects this GRUB line:

```grub
devicetree dtbs/<kernel-version>/qcom/sc8280xp-lenovo-thinkpad-x13s.dtb
```

On this machine GRUB failed with:

```text
error: invalid file name `dtbs/6.12.84/qcom/sc8280xp-lenovo-thinkpad-x13s.dtb`
```

This host overrides `boot.loader.grub.extraPerEntryConfig` so the DTB path is
addressed through the same GRUB drive variable used by the kernel and initrd:

```grub
devicetree ($drive1)//dtbs/<kernel-version>/qcom/sc8280xp-lenovo-thinkpad-x13s.dtb
```

Keep that override in `hardware/bootloader.nix` until the upstream X13s module
or NixOS GRUB generation handles this correctly.

## Disk Layout

The install wipes `/dev/nvme0n1` and creates:

- `/dev/nvme0n1p1`: EFI system partition, vfat, mounted at `/boot`
- `/dev/nvme0n1p2`: LUKS2 container opened as `root`
- `/dev/mapper/root`: btrfs filesystem with subvolumes:
  - `root`, mounted at `/` and recreated on every boot
  - `nix`, mounted at `/nix`
  - `persist`, mounted at `/persist`

The repo config currently references these fixed device paths.

## Install From Ubuntu Live ARM USB

Install tools in the live environment:

```bash
sudo apt-get update
sudo apt-get install -y btrfs-progs cryptsetup dosfstools efibootmgr gdisk git jq nix-bin rsync
```

Prepare the disk:

```bash
sudo swapoff -a || true
sudo umount -R /mnt 2>/dev/null || true
sudo cryptsetup close root 2>/dev/null || true

sudo wipefs -af /dev/nvme0n1
sudo sgdisk --zap-all /dev/nvme0n1
sudo sgdisk -n 1:1MiB:+1075MiB -t 1:EF00 -c 1:ESP /dev/nvme0n1
sudo sgdisk -n 2:0:0 -t 2:8309 -c 2:root-luks /dev/nvme0n1
sudo partprobe /dev/nvme0n1

sudo cryptsetup luksFormat --type luks2 /dev/nvme0n1p2
sudo cryptsetup open /dev/nvme0n1p2 root
sudo mkfs.vfat -F 32 -n NIXBOOT /dev/nvme0n1p1
sudo mkfs.btrfs -f -L nixos-root /dev/mapper/root

sudo mount /dev/mapper/root /mnt
sudo btrfs subvolume create /mnt/root
sudo btrfs subvolume create /mnt/nix
sudo btrfs subvolume create /mnt/persist
sudo umount /mnt

sudo mount -o subvol=root /dev/mapper/root /mnt
sudo mkdir -p /mnt/boot /mnt/nix /mnt/persist /mnt/partition-root
sudo mount -o subvol=nix,compress=zstd,noatime /dev/mapper/root /mnt/nix
sudo mount -o subvol=persist,compress=zstd,noatime /dev/mapper/root /mnt/persist
sudo mount /dev/mapper/root /mnt/partition-root
sudo mount /dev/nvme0n1p1 /mnt/boot
sudo mkdir -p /mnt/persist/etc/ssh /mnt/persist/var/lib
```

The Ubuntu live overlay is too small for the full desktop closure. Put the repo,
Nix store, cache, and temp directory on the target disk:

```bash
sudo mkdir -p /mnt/src/nixos /mnt/root-cache /mnt/tmp /mnt/nix
sudo chown -R ubuntu:ubuntu /mnt/src

rsync -a --delete --exclude .git /path/to/this/repo/ ubuntu@<live-ip>:/mnt/src/nixos/

sudo systemctl stop nix-daemon.socket nix-daemon.service
sudo rsync -aHAX --numeric-ids /nix/ /mnt/nix/
sudo mount --bind /mnt/nix /nix
sudo systemctl start nix-daemon.socket nix-daemon.service
```

Build and install on the X13s:

```bash
cd /mnt/src/nixos
sudo env XDG_CACHE_HOME=/mnt/root-cache TMPDIR=/mnt/tmp \
  nix --extra-experimental-features 'nix-command flakes' \
  build --impure .#nixosConfigurations.l-x13s.config.system.build.toplevel

sudo env XDG_CACHE_HOME=/mnt/root-cache TMPDIR=/mnt/tmp \
  nix --extra-experimental-features 'nix-command flakes' \
  run github:NixOS/nixpkgs/nixos-25.11#nixos-install -- \
  --impure --no-root-passwd --flake path:/mnt/src/nixos#l-x13s
```

Create or refresh the NVRAM boot entry if needed:

```bash
sudo efibootmgr -c -d /dev/nvme0n1 -p 1 -L NixOS -l '\EFI\BOOT\BOOTAA64.EFI'
```

## Pre-Reboot Checks

Before rebooting, confirm:

```bash
test -e /mnt/boot/EFI/BOOT/BOOTAA64.EFI
test -e /mnt/boot/dtbs/*/qcom/sc8280xp-lenovo-thinkpad-x13s.dtb
test -e /mnt/nix/var/nix/profiles/system/kernel
test -e /mnt/nix/var/nix/profiles/system/initrd
grep -F 'devicetree ($drive1)//dtbs/' /mnt/boot/grub/grub.cfg
btrfs subvolume list /mnt/partition-root
findmnt /mnt /mnt/nix /mnt/persist /mnt/partition-root /mnt/boot
sudo efibootmgr -v
```

The `NixOS` EFI entry should point at `\EFI\BOOT\BOOTAA64.EFI` on the new ESP.
`/mnt/partition-root` should show `root`, `nix`, and `persist` btrfs
subvolumes before rebooting.
