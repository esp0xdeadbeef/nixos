# s-tau one-time install runbook

This document is the install and recovery runbook for `s-tau`. It should be
safe to publish: use placeholders in this file, and keep credentials, private
keys, service tags, management addresses, disk serials, and generated unlock
secrets out of documentation and commits unless they are intentionally encrypted.

The host uses:

- Disko for install-time partitioning.
- IDSDM as the EFI system partition mounted at `/boot`.
- RAID0 across the two NVMe root members.
- LUKS container name `crypted`.
- Btrfs subvolumes `/`, `/nix`, `/persist`, and `/vmstore`.
- Lanzaboote with `boot.lanzaboote.pkiBundle = "/persist/etc/secureboot"`.
- Clevis/Tang unlock for the root LUKS device.
- SOPS for the installed user's password and host secrets.

Do not use `nixos-anywhere` for this host until this manual path has been
validated again.

## Public-repo rules

Never commit or paste:

- Plaintext passwords or passphrases.
- iDRAC credentials, Redfish session tokens, service tags, or serial numbers.
- Secure Boot private keys from `/persist/etc/secureboot` or `/var/lib/sbctl`.
- The root SOPS age private key.
- Disk IDs that include serial numbers.
- Command output that includes the above values.

The examples below use placeholders such as `<installer-host>`, `<idrac-host>`,
`<tang-host>`, and `<admin-user>`. Resolve them locally during installation.

## Variables

Set these on the workstation before copying commands:

```bash
export HOST=s-tau
export REPO="$HOME/github/nixos"
export INSTALLER_HOST="<installer-host>"
export ADMIN_USER="<admin-user>"
export TANG_URL="http://<tang-host>:<tang-port>"
export IDRAC_HOST="<idrac-host>"
```

Set these inside the installer shell:

```bash
export HOST=s-tau
export REPO=/home/nixos/github/nixos
export DISKO="$REPO/nixos/server/s-tau/build_disko/build_disko.nix"
export LUKS_KEY=/tmp/s-tau-luks.key
export TANG_URL="http://<tang-host>:<tang-port>"
```

Use high-entropy temporary passphrases generated locally. Do not reuse or
commit them.

## Dell firmware and iDRAC automation

The normal boot entry should stay boring. Dell firmware tooling is available in
the `upgrade-firmware` specialisation so update-only dependencies, `fwupd`, Dell
SUU/DSU, OpenManage Ansible, and permissive kernel parameters do not become the
default runtime.

If iDRAC credentials are stored with `sops-nix`, enable the Dell profile mapping
only after the encrypted keys exist in `secrets/s-tau-root.yaml`:

```nix
local.server.dell.idrac.sops.enable = true;
```

Default secret names and paths:

```text
dell/idrac-host     -> /run/secrets/dell/idrac-host
dell/idrac-user     -> /run/secrets/dell/idrac-user
dell/idrac-password -> /run/secrets/dell/idrac-password
```

The `dell-idrac-*` wrappers read those files automatically. Explicit
`IDRAC_HOST`, `IDRAC_USER`, `IDRAC_PASSWORD`, or `*_FILE` environment variables
still override the defaults for one-off use. Do not enable the mapping before
the encrypted secret keys exist, because activation must be able to decrypt
every declared secret.

After booting the `upgrade-firmware` specialisation, firmware checks can use the
OpenManage wrappers:

```bash
sudo dell-idrac-firmware-report
sudo dell-idrac-firmware-update --yes
```

The report path uses Dell's online repository by default and does not apply
updates. The update path is intentionally gated behind `--yes`.

For iDRAC HTTPS certificate import:

```bash
sudo IDRAC_CERT_PATH=/path/to/idrac.crt dell-idrac-import-https-cert
```

For reproducible install bootstrapping, serve a NixOS installer ISO from a
plain LAN HTTP/NFS endpoint that iDRAC8 can read, then one-shot boot it through
virtual media:

```bash
sudo NIXOS_ISO_URL="http://<lan-host>/nixos-installer.iso" dell-idrac-nixos-boot-iso
```

After the installer boots, SSH into the installer and continue with the Disko
and `nixos-install` steps below. Avoid authenticated HTTPS shares for iDRAC8
virtual media; this generation is picky about share protocols.

The SUU GUI is still available from rofi/i3 in the firmware specialisation. It
asks whether to refresh Dell's online catalog before opening. A refresh runs DSU
first, backs up the previous `Catalog.xml` as `Catalog-YYYY-MM-DD_HH-MM-SS.xml`,
writes a current online SUU source under `/var/cache/dell/suu/online-source`,
clears stale SUU runtime files under `/var/cache/dell/dell_dup/suu`, and points
the GUI compliance run at the refreshed repository instead of the old ISO
catalog.

OpenManage is the preferred non-GUI path for:

- firmware compliance reports and scheduled updates;
- iDRAC HTTPS certificate import;
- virtual-media insertion and one-shot ISO boot.

OpenManage is not the complete Secure Boot solution on this R730/iDRAC8
generation. Use the installed OS `sbctl` flow and the iDRAC/BIOS Custom policy
flow below for custom PK/KEK/db enrollment. Treat iDRAC Secure Boot automation
on this generation as useful for key reset/policy changes, not as the source of
truth for importing the sbctl key set.

## 1. Boot installer

1. Boot a NixOS installer ISO through local console or iDRAC virtual media.
2. If the ISO is not visible, temporarily disable firmware Secure Boot.
3. Start SSH on the installer and set a temporary installer password if needed.
4. Confirm access from the workstation:

```bash
ssh nixos@"$INSTALLER_HOST" id
```

Keep installer passwords out of shell history where possible.

## 2. Verify disks

Before any destructive command, verify the disk map from the installer:

```bash
ssh nixos@"$INSTALLER_HOST" '
  lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,MODEL,MOUNTPOINTS
  find /dev/disk/by-path -maxdepth 1 -type l -printf "%f -> %l\n" | sort
'
```

Disko targets non-serial `/dev/disk/by-path` names in
`nixos/server/s-tau/build_disko/build_disko.nix`:

The Dell BIOS setting `BIOS.SlotBifurcation.Slot4Bif` must be `x8x8`; with
`x4x4x4x4` only one NVMe root member was visible to Linux.

```text
boot   -> /dev/disk/by-path/pci-0000:00:1a.0-usb-0:1.3:1.0-scsi-0:0:0:0
root-a -> /dev/disk/by-path/pci-0000:82:00.0-nvme-1
root-b -> /dev/disk/by-path/pci-0000:83:00.0-nvme-1
```

Confirm each path exists and points to the intended device:

```bash
for dev in \
  /dev/disk/by-path/pci-0000:00:1a.0-usb-0:1.3:1.0-scsi-0:0:0:0 \
  /dev/disk/by-path/pci-0000:82:00.0-nvme-1 \
  /dev/disk/by-path/pci-0000:83:00.0-nvme-1
do
  readlink -f "$dev"
done
```

Abort if any path is missing, points at installer media, or points at an
unexpected disk.

## 3. Copy repo

From the workstation:

```bash
ssh nixos@"$INSTALLER_HOST" 'mkdir -p ~/github'
rsync -az --delete "$REPO/" nixos@"$INSTALLER_HOST":~/github/nixos/
```

## 4. Partition and mount

From the workstation, enter a root shell on the installer:

```bash
ssh nixos@"$INSTALLER_HOST"
sudo -i
export HOST=s-tau
export REPO=/home/nixos/github/nixos
export DISKO="$REPO/nixos/server/s-tau/build_disko/build_disko.nix"
export LUKS_KEY=/tmp/s-tau-luks.key
cd "$REPO"

read -rsp "temporary LUKS passphrase: " LUKS_PASSPHRASE
printf '\n'
printf '%s' "$LUKS_PASSPHRASE" > "$LUKS_KEY"
chmod 600 "$LUKS_KEY"

nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- \
  --yes-wipe-all-disks \
  --mode destroy,format,mount "$DISKO"

cryptsetup open --test-passphrase /dev/disk/by-id/md-name-any:root --key-file "$LUKS_KEY"
unset LUKS_PASSPHRASE
```

Expected layout after Disko:

- `/boot` mounted from the IDSDM ESP.
- `/dev/md/root` assembled from both NVMe root members.
- LUKS container `crypted`.
- Btrfs subvolumes mounted at `/mnt`, `/mnt/nix`, `/mnt/persist`, and
  `/mnt/vmstore`.

## 5. Generate hardware config

Inside the installer:

```bash
nixos-generate-config --root /mnt
mkdir -p /persist
mount --bind /mnt/persist /persist
```

From the workstation:

```bash
rsync -az \
  nixos@"$INSTALLER_HOST":/mnt/etc/nixos/hardware-configuration.nix \
  "$REPO/nixos/server/s-tau/hardware/hardware-configuration.nix"

rsync -az --delete "$REPO/" nixos@"$INSTALLER_HOST":~/github/nixos/
```

Review the generated hardware file before committing. UUIDs are expected; disk
serials and service tags are not.

## 6. Create Secure Boot keys

Inside the installer as root:

```bash
nix-shell -p sbctl --run 'sbctl create-keys'

install -d -m 0700 /mnt/persist/var/lib/sbctl
cp -a /var/lib/sbctl/. /mnt/persist/var/lib/sbctl/

install -d -m 0700 /mnt/persist/etc/secureboot
cp -a /mnt/persist/var/lib/sbctl/. /mnt/persist/etc/secureboot/

test -f /mnt/persist/etc/secureboot/keys/db/db.pem
test -f /mnt/persist/etc/secureboot/keys/db/db.key
```

Optional, for manual firmware enrollment UI only:

```bash
nix-shell -p openssl --run \
  'openssl x509 -outform der -in /mnt/persist/etc/secureboot/keys/PK/PK.pem -out /mnt/boot/PK.cer'
nix-shell -p openssl --run \
  'openssl x509 -outform der -in /mnt/persist/etc/secureboot/keys/KEK/KEK.pem -out /mnt/boot/KEK.cer'
nix-shell -p openssl --run \
  'openssl x509 -outform der -in /mnt/persist/etc/secureboot/keys/db/db.pem -out /mnt/boot/db.cer'
```

The private keys under `/mnt/persist/etc/secureboot` are host-private. Losing
them means future UKIs cannot be signed with the enrolled keys.

## 7. Create SOPS host key

Inside the installer as root:

```bash
install -d -m 0700 /mnt/persist/root/.ssh
test -f /mnt/persist/root/.ssh/id_ed25519 || \
  ssh-keygen -t ed25519 -N "" -f /mnt/persist/root/.ssh/id_ed25519 -q

install -d -m 0700 /mnt/persist/root/.config/sops/age
nix-shell -p ssh-to-age --run \
  'ssh-to-age -private-key -i /mnt/persist/root/.ssh/id_ed25519 > /mnt/persist/root/.config/sops/age/keys.txt'

chmod 600 /mnt/persist/root/.config/sops/age/keys.txt
nix-shell -p age --run \
  'age-keygen -y /mnt/persist/root/.config/sops/age/keys.txt'
```

Add only the printed public age key to `secrets/.sops.yaml` under the `s-tau`
creation rule. Then create or update `secrets/s-tau-root.yaml` from the
workstation with SOPS. Do not read decrypted secret values into logs or commits.

Push the encrypted secret update back to the installer:

```bash
rsync -az --delete "$REPO/" nixos@"$INSTALLER_HOST":~/github/nixos/
```

## 8. Create Clevis/Tang unlock material

Tang must be reachable from initrd networking before the LUKS prompt. Keep the
Tang URL site-local; do not put the real address in public docs.

Inside the installer as root:

```bash
export HOST=s-tau
export REPO=/home/nixos/github/nixos
export TANG_URL="http://<tang-host>:<tang-port>"
cd "$REPO/nixos/server/s-tau/hardware/disks"
TANG_URL="$TANG_URL" ./clevis-init-jwe.sh
```

The script prompts for the current LUKS passphrase, creates a generated Clevis
key, adds it to the LUKS keyslots, verifies it, and writes:

```text
/tmp/root-raid0.jwe
```

Copy the JWE into the repo path expected by the NixOS module:

```bash
install -m 0600 /tmp/root-raid0.jwe "$REPO/nixos/server/s-tau/hardware/disks/root-raid0.jwe"
```

Treat this JWE as unlock material. If the repo is public, either keep the file
encrypted/out-of-tree in your publication workflow or explicitly accept the
risk and rotate the LUKS keyslot/Tang binding after exposure.

From the workstation:

```bash
rsync -az \
  nixos@"$INSTALLER_HOST":~/github/nixos/nixos/server/s-tau/hardware/disks/root-raid0.jwe \
  "$REPO/nixos/server/s-tau/hardware/disks/root-raid0.jwe"

rsync -az --delete "$REPO/" nixos@"$INSTALLER_HOST":~/github/nixos/
```

## 9. Install NixOS

Inside the installer as root:

```bash
export HOST=s-tau
export REPO=/home/nixos/github/nixos
cd "$REPO"
nix --extra-experimental-features 'nix-command flakes' run github:NixOS/nixpkgs/nixos-26.05#nixos-install -- \
  --impure \
  --flake "path:$REPO#$HOST" \
  --no-root-passwd
```

Enroll Secure Boot keys while the firmware is still in setup mode:

```bash
sudo sbctl enroll-keys \
  --microsoft \
  --ignore-immutable \
  --yes-this-might-brick-my-machine
nix-shell -p sbctl --run 'sbctl status'
```

If setup mode is already disabled and `sudo sbctl list-enrolled-keys` does not
show `Platform Key`, `Key Exchange Key`, and `Database Key`, delete only the
Secure Boot platform key from BIOS/iDRAC. Do not reset the full BIOS. On this
iDRAC8 generation, Redfish exposes that as `SecureBoot.ResetKeys` with
`DeletePK`. Reboot once, confirm `sudo sbctl status` reports setup mode
enabled, rerun the enrollment command above, and leave firmware Secure Boot
disabled until the first signed UKI boot has been verified.

## 10. First boot

Reboot from the installer:

```bash
systemctl reboot
```

After the host comes up, verify from the workstation:

```bash
ssh "$ADMIN_USER@$HOST" '
  hostname
  systemctl is-system-running || true
  readlink -f /run/current-system
  readlink -f /run/booted-system
  sudo sbctl status
  sudo sbctl verify \
    /boot/EFI/systemd/systemd-bootx64.efi \
    /boot/EFI/BOOT/BOOTX64.EFI \
    /boot/EFI/Linux/*.efi
  sudo bootctl status | sed -n "1,180p"
'
```

Expected:

- Hostname is `s-tau`.
- Current and booted systems are the same after reboot.
- `bootctl status` shows the current stub as `lanzastub`.
- The default boot entry is a Type 2 UKI under `/boot/EFI/Linux`.
- The explicit `sbctl verify` command reports the active EFI boot artifacts as
  signed.

Do not sign, move, or delete `/boot/EFI/nixos/kernel-*.efi` or
`/boot/EFI/nixos/initrd-*.efi`. Lanzaboote thin stubs under `/boot/EFI/Linux`
load those payload files by content hash. A raw `sudo sbctl verify` scans the
whole ESP and may report the payload files as unsigned; that is expected for
this layout and is not a Secure Boot failure for the firmware-entered boot
artifacts.

```bash
ssh "$ADMIN_USER@$HOST" '
  sudo sbctl verify \
    /boot/EFI/systemd/systemd-bootx64.efi \
    /boot/EFI/BOOT/BOOTX64.EFI \
    /boot/EFI/Linux/*.efi
'
```

## 11. Rebuild and switch

Preferred on-host rebuild:

```bash
ssh "$ADMIN_USER@$HOST"
cd ~/github/nixos
git pull --ff-only
sudo nixos-rebuild switch --flake ".#$HOST" --show-trace
```

Remote rebuild from the workstation:

```bash
cd "$REPO"
nixos-rebuild switch --flake ".#$HOST" \
  --target-host "$HOST" \
  --use-remote-sudo \
  --show-trace
```

If the remote rebuild fails because the target does not trust local unsigned
store paths, sync or clone the repo on `s-tau` and run the preferred on-host
rebuild.

Verify after every switch:

```bash
ssh "$ADMIN_USER@$HOST" '
  systemctl is-system-running || true
  readlink -f /run/current-system
  sudo sbctl verify \
    /boot/EFI/systemd/systemd-bootx64.efi \
    /boot/EFI/BOOT/BOOTX64.EFI \
    /boot/EFI/Linux/*.efi
  sudo bootctl status | sed -n "1,180p"
'
```

## 12. Enable firmware Secure Boot

Only enable firmware enforcement after:

- Lanzaboote is enabled in the config.
- `/persist/etc/secureboot/keys/db/db.key` exists on the installed host.
- `sudo sbctl list-enrolled-keys` shows the sbctl `Platform Key`,
  `Key Exchange Key`, and `Database Key`.
- `bootctl status` shows a Lanzaboote UKI as the default boot entry.
- The explicit `sbctl verify` command above reports all active EFI boot
  artifacts signed.

Use the iDRAC8 UI:

1. Log in to iDRAC at `<idrac-host>`.
2. Go to BIOS settings.
3. Confirm boot mode is UEFI.
4. Set Secure Boot policy to Custom.
5. Set Secure Boot to Enabled.
6. Apply the change for the next reboot.
7. Reboot the host from the OS or iDRAC.

Do not use the Standard policy for this install. On this machine, Standard
policy used only the firmware/vendor trust database and rejected the IDSDM
`Linux Boot Manager` even though the files were signed. Custom policy plus the
enrolled sbctl keys is the verified working state.

Optional Redfish checks, without putting credentials in history:

```bash
read -rsp "iDRAC password: " IDRAC_PASSWORD
printf '\n'

curl -k -u "<idrac-user>:${IDRAC_PASSWORD}" \
  "https://$IDRAC_HOST/redfish/v1/Systems/System.Embedded.1/SecureBoot"

curl -k -u "<idrac-user>:${IDRAC_PASSWORD}" \
  "https://$IDRAC_HOST/redfish/v1/Systems/System.Embedded.1/Bios"

unset IDRAC_PASSWORD
```

If the firmware trust database is wrong, delete only the platform key, then
enroll from the installed OS:

```bash
read -rsp "iDRAC password: " IDRAC_PASSWORD
printf '\n'

curl -k -u "<idrac-user>:${IDRAC_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '{"ResetKeysType":"DeletePK"}' \
  "https://$IDRAC_HOST/redfish/v1/Systems/System.Embedded.1/SecureBoot/Actions/SecureBoot.ResetKeys"

unset IDRAC_PASSWORD

systemctl reboot

sudo sbctl status
sudo sbctl enroll-keys \
  --microsoft \
  --ignore-immutable \
  --yes-this-might-brick-my-machine
sudo sbctl list-enrolled-keys
```

On iDRAC8, enabling Secure Boot was tested through BIOS pending settings plus a
BIOS config job:

```bash
read -rsp "iDRAC password: " IDRAC_PASSWORD
printf '\n'

curl -k -u "<idrac-user>:${IDRAC_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X PATCH \
  -d '{"Attributes":{"SecureBoot":"Enabled","SecureBootPolicy":"Custom"}}' \
  "https://$IDRAC_HOST/redfish/v1/Systems/System.Embedded.1/Bios/Settings"

ssh "<idrac-user>@$IDRAC_HOST" \
  racadm jobqueue create BIOS.Setup.1-1 -r pwrcycle -s TIME_NOW

unset IDRAC_PASSWORD
```

Some iDRAC8 firmware also exposes Secure Boot changes through the SecureBoot
resource, but the BIOS pending settings path above is the one tested here.

After reboot with firmware Secure Boot enabled:

```bash
ssh "$ADMIN_USER@$HOST" '
  sudo sbctl status
  sudo sbctl verify \
    /boot/EFI/systemd/systemd-bootx64.efi \
    /boot/EFI/BOOT/BOOTX64.EFI \
    /boot/EFI/Linux/*.efi
  sudo bootctl status | sed -n "1,180p"
  dmesg | grep -i "secure boot" || true
'
```

Expected:

- `sbctl status` reports Secure Boot enabled.
- The explicit `sbctl verify` command reports signed active EFI boot artifacts.
- `bootctl status` still reports `lanzastub`.

## 13. Recovery notes

If Secure Boot blocks boot:

1. Use iDRAC to disable firmware Secure Boot.
2. Boot the installed system or the installer ISO.
3. Check iDRAC lifecycle logs for `UEFI0073`. That means firmware policy
   rejected the boot option before Linux started.
4. Confirm `/persist/etc/secureboot` still contains the signing keys.
5. Run `sudo sbctl list-enrolled-keys`. If it only shows vendor keys, use the
   `DeletePK` and `sbctl enroll-keys` flow above.
6. Run `sudo nixos-rebuild switch --flake ".#s-tau"`.
7. Run the explicit active-artifact `sbctl verify` command above.
8. Re-enable firmware Secure Boot only with policy `Custom` after the
   verification gates pass.

If Clevis/Tang unlock fails:

1. Enter the manual LUKS passphrase on the console.
2. Verify initrd networking and Tang reachability.
3. Regenerate the JWE with `clevis-init-jwe.sh`.
4. Rebuild so the initrd contains the updated JWE.
5. Remove the obsolete LUKS keyslot after confirming the new one works.

If disk paths change:

1. Boot the installer.
2. Re-run the disk verification commands.
3. Update `build_disko/build_disko.nix` with non-serial stable paths.
4. Do not commit command output containing disk serials.
