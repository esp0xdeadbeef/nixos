# l-portal-unstable

Variant of `l-portal` (same physical ThinkPad X13s) built against the
nixos-hardware x13s rework from [NixOS/nixos-hardware#1751], tracked as the
dedicated, rev-pinned flake input `nixos-hardware-x13s`.

It exists so the port can be built, booted and compared without touching the
known-good `l-portal`, which stays the rollback target.

## Differences from l-portal

- Board support comes from the `x13s` module on the PR branch instead of the
  pinned `nixos-hardware` input.
- The four TPM patches are no longer carried locally in `hardware/tpm.nix`
  (removed here); they are selected through the module's
  `hardware.x13s.patches.tpm.enable`. Importing both would apply the series
  twice and fail the patch phase.
- `hardware.lenovo.x13s.wifiMAC = ""` keeps the SOPS-backed udev rule in
  `default.nix` as the sole owner of the Wi-Fi address, instead of letting the
  module generate a machine-id-derived MAC for the same device.
- Machine identity stays `l-portal`: same SOPS files, same age/SSH keys, same
  `home-manager` tree (`local.homeManager.hostName`). Only the flake attribute
  name and the system hostname differ.

## Deployment record

Last deployed and booted generation:

| | |
| --- | --- |
| flake attribute | `l-portal-unstable` |
| system | `ywb1xrzwkg2k0l5yyxva9a2m0b7nbsqz-nixos-system-l-portal-unstable-26.05.20261105.c56a87d` |
| kernel | 6.18.60 (patched, `radg7qx1fcadsb13a1xa6s0r5fdl47cb`) |
| boot generation | 267, systemd-boot default |
| rollback target | `0khmwhg65dvv8g8ngvwvh18kz3sf2xvv-nixos-system-l-portal-26.05.20261105.c56a87d` |

To deploy: build the flake attribute, copy the closure to the machine, set the
system profile and run `switch-to-configuration boot`, then reboot into the new
generation. The closure must be imported with root (`sudo nix-store --import`)
when the build happened elsewhere, because locally built paths carry no
substituter signature.

## Verified on hardware

Deployed and booted on the X13s (100.64.0.14), kernel 6.18.60 with the patched
TPM driver built in:

```
qcom_qseecom qcom_qseecom: setting up client for qcom.tz.tpm
tpm_qcom_qsee.tpm_qcom_qsee qcom_qseecom.tpm.0: using dTPM TPM backend
```

`/dev/tpm0` and `/dev/tpmrm0` appear, and root unlocks through the full chained
binding (Tang **and** TPM2):

```
tpm2-startup: TPM2_Startup(CLEAR)
clevis: trying /etc/clevis/root-0.jwe
clevis: unlocked via /etc/clevis/root-0.jwe
```

The dTPM acceptance in the log comes from patch 0004, which is the X13s-specific
one: the SC8280XP reports `QCOM_TPM_TYPE_DTPM`, not fTPM.

## Rollback

The machine boots one generation at a time; `l-portal` generations remain in the
boot menu, so reverting is `nixos-rebuild boot --rollback` or selecting the
previous entry at the systemd-boot menu.

[NixOS/nixos-hardware#1751]: https://github.com/NixOS/nixos-hardware/pull/1751

---

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

`l-portal` unlocks root through Clevis/Tang during initrd.

There is **one JWE per Tang site**, not one combined binding:

| file | Tang server | site |
| --- | --- | --- |
| `hardware/root-neon.jwe`   | `http://192.168.1.75:7500` | neon  |
| `hardware/root-cobalt.jwe` | `http://10.2.90.10:7500`   | cobalt (l-envil unlock plane, VLAN 90) |

All of them wrap the *same* LUKS keyslot secret and are staged into the initrd
together. At boot `clevis-try-bindings-root.service` walks them in the order
listed in `hardware/bootloader.nix` `secretFiles`; the first whose Tang answers
unlocks root, and the rest are skipped. If none answer, boot falls back to the
normal LUKS passphrase prompt.

This split exists so each binding can be generated **from the site it belongs
to**: only the Tang server of the site you are currently at has to be
reachable. A single combined SSS JWE cannot be regenerated from one site alone,
because `clevis encrypt sss` fetches every pin's advertisement live (with no
timeout, so an unreachable server hangs the bind).

### Staging a binding for a site

Run from the site whose Tang you are binding:

```bash
cd ~/github/nixos/nixos/laptop/l-portal/hardware
sudo -E ./clevis-init-jwe.sh --site cobalt     # or: --site neon
```

The script:

- checks that site's Tang advertisement is reachable (fails fast, 10s timeout),
- prompts for the current root LUKS passphrase,
- writes `root-<site>.jwe`,
- verifies the new JWE decrypts **before** touching LUKS,
- adds and verifies the LUKS keyslot.

`--site` is required; `--url` overrides the endpoint (e.g. a relocated Tang).
Sites and their endpoints live in `SITE_TANG_URLS` at the top of the script —
add an entry there and in `secretFiles` when a new Tang server appears.

If `root-<site>.jwe` is not yet listed in `hardware/bootloader.nix`
`secretFiles`, add it:

```nix
    secretFiles = [
      ./root-neon.jwe
      ./root-cobalt.jwe
    ];
```

### Making a new JWE take effect

The JWE is **baked into the initrd**, so rewriting the file is not enough:

```bash
git add nixos/laptop/l-portal/hardware/root-<site>.jwe
git commit -m "fix(l-portal): rebind root LUKS to <site> tang"
sudo nixos-rebuild boot --flake path:$HOME/github/nixos#l-portal
```

Verify before rebooting that the new initrd carries the bindings:

```bash
nix shell nixpkgs#cpio nixpkgs#zstd -c bash -c \
  'lsinitrd /boot/EFI/nixos/*initrd* 2>/dev/null | grep clevis'
```

Note `lsinitrd` is not installed on l-portal by default.

The `tang.host` / `tang.port` options in `hardware/bootloader.nix` are
documentation only; the real endpoints are baked into the per-site JWEs.

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

The JWE is not the Wi-Fi password; it is the Tang-wrapped random unlock key.

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

Refresh the per-site Clevis bindings so initrd receives the new unlock secret
(run once per site, from that site):

```bash
cd /home/deadbeef/github/nixos/nixos/laptop/l-portal/hardware
sudo -E ./clevis-init-jwe.sh --site cobalt
sudo -E ./clevis-init-jwe.sh --site neon
```

Rebuild after committing the updated `root-<site>.jwe` files:

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
test -e /mnt/src/nixos/nixos/laptop/l-portal/hardware/root-cobalt.jwe
ls /mnt/src/nixos/nixos/laptop/l-portal/hardware/root-*.jwe
sudo efibootmgr -v
```

The `Linux Boot Manager` EFI entry should point at
`\EFI\systemd\systemd-bootaa64.efi` on the new ESP.
`/mnt/partition-root` should show `root`, `nix`, and `persist` btrfs
subvolumes before rebooting.
