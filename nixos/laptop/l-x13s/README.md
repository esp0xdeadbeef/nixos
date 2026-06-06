# l-x13s NixOS install

The ThinkPad X13s is `aarch64-linux`. Build and install this host on the X13s
itself, or configure a native ARM builder. Building it on plain `x86_64-linux`
fails while evaluating/building X13s DTBs.

## Bootloader

This host uses systemd-boot on the ESP. The generated loader entry includes the
X13s DTB through a systemd-boot `devicetree` line.

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

Prepare the disk with disko. This wipes `/dev/nvme0n1`.

```bash
sudo swapoff -a || true
sudo umount -R /mnt 2>/dev/null || true
sudo cryptsetup close root 2>/dev/null || true

printf '<luks-password>' | sudo tee /tmp/disk.key >/dev/null
sudo chmod 600 /tmp/disk.key

sudo nix --extra-experimental-features 'nix-command flakes' \
  run github:nix-community/disko/latest -- \
  --mode destroy,format,mount --yes-wipe-all-disks \
  /path/to/this/repo/nixos/laptop/l-x13s/disko.nix

sudo mkdir -p /mnt/src/nixos /mnt/root-cache /mnt/tmp /mnt/persist/etc/ssh /mnt/persist/var/lib
sudo chown -R ubuntu:ubuntu /mnt/src
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

The installer creates or refreshes a `Linux Boot Manager` NVRAM entry for
systemd-boot. A fallback removable path is also installed at
`\EFI\BOOT\BOOTAA64.EFI`.

Remove the temporary live-system key file after installation:

```bash
sudo rm -f /tmp/disk.key
```

## Pre-Reboot Checks

Before rebooting, confirm:

```bash
test -e /mnt/boot/EFI/BOOT/BOOTAA64.EFI
test -e /mnt/boot/EFI/systemd/systemd-bootaa64.efi
test -e /mnt/boot/EFI/nixos/*sc8280xp-lenovo-thinkpad-x13s.dtb.efi
test -e /mnt/nix/var/nix/profiles/system/kernel
test -e /mnt/nix/var/nix/profiles/system/initrd
grep -F 'devicetree /EFI/nixos/' /mnt/boot/loader/entries/nixos-generation-1.conf
btrfs subvolume list /mnt/partition-root
findmnt /mnt /mnt/nix /mnt/persist /mnt/partition-root /mnt/boot
sudo efibootmgr -v
```

The `Linux Boot Manager` EFI entry should point at
`\EFI\systemd\systemd-bootaa64.efi` on the new ESP.
`/mnt/partition-root` should show `root`, `nix`, and `persist` btrfs
subvolumes before rebooting.
