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

The swap partition is persistent LUKS, not random encrypted swap. Hibernate
requires the resume image to survive reboot, so `randomEncryption = true` is not
compatible with this host. The initrd opens `root` first, either through the
default Clevis/Tang boot entry or through the `manual-unlock` boot entry. After
`/persist` is available from the unlocked root filesystem, initrd opens
`cryptswap` with a staged copy of `/persist/etc/diskunlock/cryptswap.key` and
uses it as the resume device. The staging is required because hibernate resume
must run before the normal `/sysroot/persist` mount exists.

Expected runtime state:

```bash
cat /proc/cmdline | grep -o 'resume=[^ ]*'
# resume=/dev/mapper/cryptswap

lsblk -o NAME,TYPE,FSTYPE,LABEL,PARTLABEL,UUID /dev/nvme0n1
# nvme0n1p2 should be crypto_LUKS, opened as cryptswap

swapon --show
# /dev/mapper/cryptswap should be active
```

## Initrd Wi-Fi Unlock

`l-portal` unlocks root through Clevis/Tang during initrd. The Tang binding is
an SSS pin with threshold 1 over two Tang servers (any one reachable suffices):

- neon: `http://192.168.1.75:7500`
- cobalt: `http://10.2.90.10:7500` (dedicated Tang server on l-envil's unlock
  plane, VLAN 90)

The `tang.host` / `tang.port` options in `hardware/bootloader.nix` are
documentation only; the real endpoints are baked into `root.jwe` by
`clevis-init-jwe.sh` (see `TANG_URLS` there).

The initrd Wi-Fi config is SOPS-managed (`secrets/l-portal-initrd-wifi.yaml`,
binary format) and contains both the neon `diskunlock` and cobalt
`cobalt-unlock` networks. sops-nix decrypts it at activation and bakes it into
the initrd; the age key never enters the initrd. Because `nixos-rebuild switch`
installs the bootloader before running sops-nix's activation hook, provision
the secret first whenever it changes:

```bash
sudo nixos-rebuild test --flake .#l-portal    # decrypt sops secrets to /run/secrets
sudo nixos-rebuild switch --flake .#l-portal  # now bake them into the initrd
```

Generate or refresh the Clevis JWE after formatting root LUKS:

```bash
cd /mnt/src/nixos/nixos/laptop/l-portal/hardware
sudo ./clevis-init-jwe.sh
```

`clevis-init-jwe.sh` defaults to binding both Tang servers
(`TANG_URLS="http://192.168.1.75:7500 http://10.2.90.10:7500"`). Override
`TANG_URLS` if the endpoints change.

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

## Swap Keyfile

`cryptswap` is unlocked with a keyfile stored inside the encrypted root
filesystem. Create it after installation or after reformatting the swap
partition:

```bash
sudo install -d -m 0700 /persist/etc/diskunlock
sudo dd if=/dev/urandom of=/persist/etc/diskunlock/cryptswap.key bs=64 count=1
sudo chmod 0400 /persist/etc/diskunlock/cryptswap.key

printf '<current-swap-luks-passphrase>' | sudo cryptsetup luksAddKey \
  /dev/disk/by-partlabel/disk-nvme0n1-swap \
  /persist/etc/diskunlock/cryptswap.key \
  --key-file -

sudo cryptsetup open --test-passphrase \
  /dev/disk/by-partlabel/disk-nvme0n1-swap \
  --key-file /persist/etc/diskunlock/cryptswap.key
```

This keyfile is encrypted at rest because it lives inside the root LUKS
container. It does not involve Clevis/Tang; Clevis only affects how `root` is
opened in the default boot entry. During initrd, a small service mounts the
persist subvolume read-only, copies the key to `/run/cryptswap.key`, unmounts
the subvolume, and only then lets `cryptswap` start.

## Rotate LUKS Passphrase

The install examples use a temporary LUKS passphrase via `/tmp/disk.key`. Do not
leave production machines on that password.

Root and swap do not need to share the same human passphrase. Rotate the root
passphrase and Clevis binding for root separately from the swap keyfile. Keep a
manual fallback passphrase on `cryptswap` only if you want to be able to recover
the swap container without the persisted keyfile.

From the running system:

```bash
old='<old-luks-passphrase>'
new='<new-luks-passphrase>'

printf '%s' "$new" > /tmp/new-luks.key
chmod 600 /tmp/new-luks.key

printf '%s' "$old" | sudo cryptsetup luksAddKey \
  /dev/disk/by-partlabel/disk-nvme0n1-luks \
  /tmp/new-luks.key \
  --key-file -
```

Verify root unlocks with the new passphrase:

```bash
printf '%s' "$new" | sudo cryptsetup open --test-passphrase \
  /dev/disk/by-partlabel/disk-nvme0n1-luks \
  --key-file -
```

Refresh the Clevis binding so initrd receives the new unlock secret:

```bash
cd /home/deadbeef/github/nixos/nixos/laptop/l-portal/hardware
sudo ./clevis-init-jwe.sh
```

Rebuild after committing or syncing the updated `root.jwe`:

```bash
cd /home/deadbeef/github/nixos
sudo nixos-rebuild switch --flake .#l-portal
```

Only after a successful reboot and hibernate test, remove the old passphrase from
the root LUKS header. Check keyslots first:

```bash
sudo cryptsetup luksDump /dev/disk/by-partlabel/disk-nvme0n1-luks
```

Then remove the old root passphrase:

```bash
printf '%s' "$old" | sudo cryptsetup luksRemoveKey \
  /dev/disk/by-partlabel/disk-nvme0n1-luks \
  --key-file -
```

To rotate the swap keyfile, add a new keyfile first, verify it, then remove the
old keyfile from the swap LUKS header:

```bash
sudo dd if=/dev/urandom of=/persist/etc/diskunlock/cryptswap.key.new bs=64 count=1
sudo chmod 0400 /persist/etc/diskunlock/cryptswap.key.new

sudo cryptsetup luksAddKey \
  /dev/disk/by-partlabel/disk-nvme0n1-swap \
  /persist/etc/diskunlock/cryptswap.key.new \
  --key-file /persist/etc/diskunlock/cryptswap.key

sudo cryptsetup open --test-passphrase \
  /dev/disk/by-partlabel/disk-nvme0n1-swap \
  --key-file /persist/etc/diskunlock/cryptswap.key.new

sudo cryptsetup luksRemoveKey \
  /dev/disk/by-partlabel/disk-nvme0n1-swap \
  --key-file /persist/etc/diskunlock/cryptswap.key

sudo mv /persist/etc/diskunlock/cryptswap.key.new \
  /persist/etc/diskunlock/cryptswap.key

rm -f /tmp/new-luks.key
```

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
