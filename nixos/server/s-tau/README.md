# s-tau manual install

`s-tau` is the rack server below `s-sigma`. Install it with the same manual
playbook style as `s-sigma`: boot a NixOS installer, rsync this repo, run Disko
manually, generate hardware config, create secure boot material, generate the
SOPS age key, generate the Clevis JWE, then run `nixos-install`.

Do not use `nixos-anywhere` for this box until this manual path is proven again.

Temporary bootstrap passwords:

- LUKS password: `nixos`
- `deadbeef` password: `nixos`

Replace both after the install is stable.

## Known device map

This is the device map observed from the NixOS installer on 2026-06-27:

```text
/dev/disk/by-id/usb-SanDisk_Cruzer_Blade_2006016481051AF20108-0:0  physical USB installer
/dev/disk/by-id/usb-DELL_IDSDM_012345678901-0:0                   internal IDSDM boot device
/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S69ENF0W826691E      NVMe root member A
/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S69ENF0W826718V      NVMe root member B
/dev/sr0                                                          iDRAC virtual CD ISO
```

Important: on this machine `/dev/sda` is the physical Cruzer Blade USB. Disko
must never target bare `/dev/sda`.

## Boot installer

1. Boot the NixOS graphical ISO from iDRAC virtual media.
2. Disable Secure Boot during setup if the ISO is not visible.
3. Confirm SSH works:

```bash
sshpass -p nixos ssh nixos@192.168.1.70 id
```

4. Confirm the disk map before any destructive command:

```bash
sshpass -p nixos ssh nixos@192.168.1.70 \
  'lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,MODEL,SERIAL,MOUNTPOINTS; find /dev/disk/by-id -maxdepth 1 -type l -printf "%f -> %l\n" | sort'
```

## Copy repo to installer

From the workstation:

```bash
rsync -va /home/deadbeef/github/nixos nixos@192.168.1.70:~/github/
```

## Partition, RAID0, LUKS, and mount

Inside the installer:

```bash
ssh nixos@192.168.1.70
sudo -i

PATH_TO_DISKO="/home/nixos/github/nixos/nixos/server/s-tau/build_disko/build_disko.nix"
printf 'nixos' > /tmp/s-tau-luks.key
chmod 600 /tmp/s-tau-luks.key

nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- \
  --yes-wipe-all-disks \
  --mode destroy,format,mount "$PATH_TO_DISKO"

cryptsetup open --test-passphrase /dev/disk/by-id/md-name-any:root --key-file /tmp/s-tau-luks.key
```

Expected layout after Disko:

- `/boot` on the Dell IDSDM.
- `/dev/md/root` as RAID0 over both Samsung NVMe partitions.
- LUKS container name `crypted`.
- Btrfs subvolumes `/root`, `/nix`, `/persist`, `/vmstore`.

## Generate hardware configuration

Inside the installer:

```bash
nixos-generate-config --root /mnt/
mkdir -p /persist
mount --bind /mnt/persist /persist
```

From the workstation:

```bash
rsync -va \
  nixos@192.168.1.70:/mnt/etc/nixos/hardware-configuration.nix \
  /home/deadbeef/github/nixos/nixos/server/s-tau/hardware/hardware-configuration.nix

rsync -va /home/deadbeef/github/nixos nixos@192.168.1.70:~/github/
```

## Secure Boot keys

Inside the installer as root:

```bash
nix-shell -p sbctl --run 'sbctl create-keys'

mkdir -p /mnt/persist/var/lib/sbctl
cp -r /var/lib/sbctl/* /mnt/persist/var/lib/sbctl

nix-shell -p openssl --run 'openssl x509 -outform der -in /mnt/persist/var/lib/sbctl/keys/PK/PK.pem -out /mnt/boot/PK.cer'
nix-shell -p openssl --run 'openssl x509 -outform der -in /mnt/persist/var/lib/sbctl/keys/KEK/KEK.pem -out /mnt/boot/KEK.cer'
nix-shell -p openssl --run 'openssl x509 -outform der -in /mnt/persist/var/lib/sbctl/keys/db/db.pem -out /mnt/boot/db.cer'

mkdir -p /persist/etc/secureboot/
cp -r /mnt/persist/var/lib/sbctl/* /persist/etc/secureboot/
```

## SOPS host key

Inside the installer as root:

```bash
[ -d /mnt ] || echo "mount /mnt first"
[ -f /mnt/persist/root/.ssh/id_ed25519 ] || (
  mkdir -p /mnt/persist/root/.ssh
  ssh-keygen -t ed25519 -N "" -f /mnt/persist/root/.ssh/id_ed25519 -q
)

mkdir -p /mnt/persist/root/.config/sops/age
nix-shell -p ssh-to-age --run \
  'bash -c "ssh-to-age -private-key -i /mnt/persist/root/.ssh/id_ed25519 > /mnt/persist/root/.config/sops/age/keys.txt"'

key=$(nix-shell -p age --run "age-keygen -y /mnt/persist/root/.config/sops/age/keys.txt")
echo -e "public key:\n$key"
```

Add the public key to `secrets/.sops.yaml`, create or update
`secrets/s-tau-root.yaml`, then re-enable the commented SOPS imports in
`nixos/server/s-tau/default.nix`.

Until that is done, tau intentionally uses the temporary `deadbeef` hash for
password `nixos`.

## Clevis/Tang auto-unlock

Tang must stay on `192.168.1.75:7500`. `192.168.1.70` is tau's initrd client
address, not the Tang server.

Inside the installer as root:

```bash
cd /home/nixos/github/nixos/nixos/server/s-tau/hardware/disks/
./clevis-init-jwe.sh
```

When prompted for the current LUKS passphrase, enter:

```text
nixos
```

The script writes `/tmp/root-raid0.jwe`.

From the workstation:

```bash
rsync -va \
  nixos@192.168.1.70:/tmp/root-raid0.jwe \
  /home/deadbeef/github/nixos/nixos/server/s-tau/hardware/disks/root-raid0.jwe

rsync -va /home/deadbeef/github/nixos nixos@192.168.1.70:~/github/
```

## Install

Inside the installer as root:

```bash
nix --extra-experimental-features 'nix-command flakes' run github:NixOS/nixpkgs/nixos-26.05#nixos-install -- \
  --impure \
  --flake path:/home/nixos/github/nixos#s-tau \
  --no-root-passwd
```

Then enroll Secure Boot keys while still in setup mode:

```bash
nix-shell -p sbctl --run 'sbctl enroll-keys -m'
```

If `sbctl status` reports `Setup Mode: Disabled`, reset Secure Boot keys from
BIOS/iDRAC first, then rerun the enroll command. The installed system can boot
with Secure Boot disabled, but Secure Boot will not work until the generated
keys are enrolled.

Reboot only after Disko, hardware config, secure boot keys, SOPS host key,
Clevis JWE, and `nixos-install` are complete.
