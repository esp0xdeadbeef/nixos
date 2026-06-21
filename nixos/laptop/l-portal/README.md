# l-portal NixOS install

The ThinkPad X13s is `aarch64-linux`. Build and install this host on the X13s
itself, or configure a native ARM builder. Building it on plain `x86_64-linux`
fails while evaluating/building X13s DTBs.

## Bootloader

This host uses systemd-boot on the ESP. The generated loader entry includes the
X13s DTB through a systemd-boot `devicetree` line.

## Disk Layout

The install wipes `/dev/nvme0n1` and creates:

- `/dev/nvme0n1p1`: EFI system partition, vfat, mounted at `/boot`
- `/dev/nvme0n1p2`: 24G LUKS2 encrypted swap partition, opened as `cryptswap`
- `/dev/nvme0n1p3`: LUKS2 container opened as `root`
- `/dev/mapper/root`: btrfs filesystem with subvolumes:
  - `root`, mounted at `/` and recreated on every boot
  - `nix`, mounted at `/nix`
  - `persist`, mounted at `/persist`

The repo config currently references these fixed device paths.

The swap is a real partition, not a swapfile. That keeps btrfs scrub simple and
avoids having scrub jobs special-case `/persist/var/lib/swapfile`.

## Initrd Wi-Fi Unlock

`l-portal` can unlock root through Clevis/Tang during initrd. The Tang server is
declared in `hardware/bootloader.nix`:

```nix
local.boot.clevisTangUnlock.tang = {
  host = "192.168.1.75";
  port = 7500;
};
```

That renders to `http://192.168.1.75:7500` for the Clevis binding. The initrd
Wi-Fi config is intentionally host-local and persisted outside git:

```bash
sudo install -d -m 0755 /persist/etc/diskunlock
sudo tee /persist/etc/diskunlock/wpa_supplicant.conf >/dev/null <<'EOF'
ctrl_interface=/run/wpa_supplicant
update_config=0
network={
    ssid="diskunlock"
    psk="Inpo3BeHLCcajYuOkFwM"
    key_mgmt=WPA-PSK
}
EOF
sudo chmod 600 /persist/etc/diskunlock/wpa_supplicant.conf
```

During a live USB install, also copy it into the target persist volume:

```bash
sudo install -d -m 0755 /mnt/persist/etc/diskunlock
sudo cp /persist/etc/diskunlock/wpa_supplicant.conf /mnt/persist/etc/diskunlock/wpa_supplicant.conf
sudo chmod 600 /mnt/persist/etc/diskunlock/wpa_supplicant.conf
```

Generate or refresh the Clevis JWE after formatting root LUKS:

```bash
cd /mnt/src/nixos/nixos/laptop/l-portal/hardware
sudo ./clevis-init-jwe.sh
```

The helper defaults to `TANG_HOST=192.168.1.75` and `TANG_PORT=7500`. Override
those environment variables before running it if the Tang endpoint changes.

Commit `nixos/laptop/l-portal/hardware/root.jwe` with the host config. The JWE
is not the Wi-Fi password; it is the Tang-wrapped random unlock key.

## Install With nixos-anywhere

This is the preferred unattended path when the live system has SSH enabled.
The host config imports its own disko layout, so `nixos-anywhere` can partition,
format, mount, and install from the flake.

On the Ubuntu live system:

```bash
sudo apt-get update
sudo apt-get install -y openssh-server
sudo systemctl enable --now ssh
```

On another machine with this repo:

```bash
printf '<luks-password>' > /tmp/disk.key
chmod 600 /tmp/disk.key

nix run github:nix-community/nixos-anywhere -- \
  --disk-encryption-keys /tmp/disk.key /tmp/disk.key \
  --flake path:/home/deadbeef/github/nixos#l-portal \
  --target-host ubuntu@<live-ip>

rm -f /tmp/disk.key
```

Use the manual path below if the live environment cannot run SSH reliably or if
you want to do the format and install steps by hand.

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
sudo cryptsetup close cryptswap 2>/dev/null || true

printf '<luks-password>' | sudo tee /tmp/disk.key >/dev/null
sudo chmod 600 /tmp/disk.key

sudo nix --extra-experimental-features 'nix-command flakes' \
  run github:nix-community/disko/latest -- \
  --mode destroy,format,mount --yes-wipe-all-disks \
  /path/to/this/repo/nixos/laptop/l-portal/disko.nix

sudo mkdir -p /mnt/src/nixos /mnt/root-cache /mnt/tmp /mnt/persist/etc/ssh /mnt/persist/var/lib
sudo chown -R ubuntu:ubuntu /mnt/src
```

Bootstrap the persisted root SSH key before installation and derive the sops age
identity from it. Add the printed age recipient to `.sops.yaml`, then run
`sops updatekeys -y secrets/l-portal-default.yaml` before installing:

```bash
sudo install -d -m 0700 /mnt/persist/root/.ssh /mnt/persist/root/.config/sops/age
sudo ssh-keygen -t ed25519 -N "" -f /mnt/persist/root/.ssh/id_ed25519 -q
sudo nix --extra-experimental-features 'nix-command flakes' \
  --accept-flake-config \
  shell nixpkgs#ssh-to-age -c ssh-to-age -private-key \
  -i /mnt/persist/root/.ssh/id_ed25519 \
  -o /mnt/persist/root/.config/sops/age/keys.txt
sudo chmod 0600 /mnt/persist/root/.ssh/id_ed25519 /mnt/persist/root/.config/sops/age/keys.txt
sudo /mnt/nix/var/nix/profiles/system/sw/bin/age-keygen \
  -y /mnt/persist/root/.config/sops/age/keys.txt
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
  --accept-flake-config \
  build --impure .#nixosConfigurations.l-portal.config.system.build.toplevel

sudo env XDG_CACHE_HOME=/mnt/root-cache TMPDIR=/mnt/tmp \
  nix --extra-experimental-features 'nix-command flakes' \
  --accept-flake-config \
  run github:NixOS/nixpkgs/nixos-26.05#nixos-install -- \
  --impure --no-root-passwd --flake path:/mnt/src/nixos#l-portal
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
swapon --show
test -e /mnt/persist/etc/diskunlock/wpa_supplicant.conf
test -e /mnt/src/nixos/nixos/laptop/l-portal/hardware/root.jwe
sudo efibootmgr -v
```

The `Linux Boot Manager` EFI entry should point at
`\EFI\systemd\systemd-bootaa64.efi` on the new ESP.
`/mnt/partition-root` should show `root`, `nix`, and `persist` btrfs
subvolumes before rebooting.
