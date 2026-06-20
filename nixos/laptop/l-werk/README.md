# l-werk rebuild

This host is installed through disko. Do not hand-create partitions or run
`nixos-generate-config` for normal rebuilds.

## Live ISO

1. Boot a NixOS live ISO in UEFI mode.
2. For Secure Boot enrollment, put the firmware in setup mode before install.
3. SSH into the live system and become root.

```bash
ssh nixos@192.168.1.151
sudo -i
```

If the live root account is used during recovery:

```bash
ssh root@192.168.1.151
```

## Copy config

From the machine that has this repo:

```bash
rsync -a --delete /home/deadbeef/github/nixos/ nixos@192.168.1.151:~/github/nixos/
```

On the live system:

```bash
sudo -i
cd /home/nixos/github/nixos
```

## Disk layout

The disko config is `nixos/laptop/l-werk/disko/build_disko.nix`.

Current layout:

- `/dev/nvme0n1p1`: BIOS boot partition
- `/dev/nvme0n1p2`: 1G EFI system partition mounted at `/boot`
- `/dev/nvme0n1p3`: LUKS encrypted swap, mapped as `cryptswap`
- `/dev/nvme0n1p4`: LUKS encrypted btrfs root, mapped as `crypted`

The temporary install password/key is `nixos`. Change it after the first boot.
`/tmp/disk.key` is only for disko/bootstrap formatting. It must not be used by
the installed initrd after reboot.

```bash
printf nixos > /tmp/disk.key
chmod 600 /tmp/disk.key

nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko/latest -- \
  --yes-wipe-all-disks \
  --mode destroy,format,mount \
  /home/nixos/github/nixos/nixos/laptop/l-werk/disko/build_disko.nix
```

## SOPS keys

Create host age keys before install and add the public keys to `.sops.yaml`.
Then re-encrypt the l-werk secrets.

```bash
mkdir -p /mnt/persist/root/.config/sops/age
mkdir -p /mnt/persist/home/deadbeef/.config/sops/age

nix shell nixpkgs#age -c age-keygen -o /mnt/persist/root/.config/sops/age/keys.txt
nix shell nixpkgs#age -c age-keygen -o /mnt/persist/home/deadbeef/.config/sops/age/keys.txt

nix shell nixpkgs#age -c age-keygen -y /mnt/persist/root/.config/sops/age/keys.txt
nix shell nixpkgs#age -c age-keygen -y /mnt/persist/home/deadbeef/.config/sops/age/keys.txt

chown -R 1000:100 /mnt/persist/home/deadbeef/.config
```

For this rebuild, `deadbeef-passwd` is set to `nixos`.

## Install

```bash
nixos-install --no-root-passwd --impure --flake path:/home/nixos/github/nixos#l-werk
```

If the repo was copied as root instead:

```bash
nixos-install --no-root-passwd --impure --flake path:/root/github/nixos#l-werk
```

## TPM unlock

Enroll both encrypted devices. Root is `p4`, encrypted swap is `p3`.
`--wipe-slot=tpm2` only wipes TPM2 tokens on the LUKS device being enrolled, so
it is safe to use once for root and once for swap.

```bash
systemd-cryptenroll --unlock-key-file=/tmp/disk.key --tpm2-device=auto --tpm2-pcrs=7 --wipe-slot=tpm2 /dev/nvme0n1p4
systemd-cryptenroll --unlock-key-file=/tmp/disk.key --tpm2-device=auto --tpm2-pcrs=7 --wipe-slot=tpm2 /dev/nvme0n1p3
```

If `/tmp/disk.key` is gone, use the current LUKS passphrase when prompted.
During this bootstrap that is `nixos`.

The runtime initrd must have no `/tmp/disk.key` dependency. Check:

```bash
nix eval .#nixosConfigurations.l-werk.config.boot.initrd.luks.devices.crypted.keyFile
nix eval .#nixosConfigurations.l-werk.config.boot.initrd.luks.devices.crypted.crypttabExtraOpts
nix eval .#nixosConfigurations.l-werk.config.boot.initrd.luks.devices.cryptswap.crypttabExtraOpts
```

Expected:

```text
null
[ "tpm2-device=auto" "tpm2-pcrs=7" ]
[ "tpm2-device=auto" "tpm2-pcrs=7" ]
```

After Secure Boot mode changes, firmware updates, or key enrollment changes,
re-enroll the TPM token from the installed system:

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --wipe-slot=tpm2 /dev/nvme0n1p4
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --wipe-slot=tpm2 /dev/nvme0n1p3
```

## Secure Boot

l-werk uses Lanzaboote with:

```nix
boot.lanzaboote.enable = true;
boot.lanzaboote.autoGenerateKeys.enable = true;
boot.lanzaboote.pkiBundle = "/persist/var/lib/sbctl";
```

After install, while the firmware is in setup mode, enroll the keys:

```bash
nixos-enter --root /mnt -c 'sbctl status'
nixos-enter --root /mnt -c 'sbctl create-keys'
nixos-install --no-root-passwd --impure --flake path:/root/github/nixos#l-werk
nixos-enter --root /mnt -c 'sbctl enroll-keys -m'
nixos-enter --root /mnt -c 'sbctl status'
```

If enrollment fails because `PK`, `KEK`, or `db` efivars are immutable, clear
the immutable bit on the mentioned efivar files and run enrollment again:

```bash
chattr -i /sys/firmware/efi/efivars/KEK-* /sys/firmware/efi/efivars/db-*
nixos-enter --root /mnt -c 'sbctl enroll-keys -m'
```

Use `-m` when Microsoft vendor keys are needed. Without Microsoft vendor keys:

```bash
nixos-enter --root /mnt -c 'sbctl enroll-keys'
```

Then enable Secure Boot in firmware and boot the installed system.

To verify signatures from the live ISO:

```bash
nix shell nixpkgs#sbsigntool -c sbverify --list /mnt/boot/EFI/BOOT/BOOTX64.EFI
nix shell nixpkgs#sbsigntool -c sbverify --list /mnt/boot/EFI/systemd/systemd-bootx64.efi
nix shell nixpkgs#sbsigntool -c sbverify --list /mnt/boot/EFI/Linux/*.efi
```

## CUDA

l-werk has an NVIDIA RTX A1000 Laptop GPU. Keep
`nixpkgs.config.cudaCapabilities = [ "8.6" ];` so CUDA packages such as
Ollama and Hashcat target this GPU instead of compiling every architecture.
The public NixOS CUDA cache is auto-enabled by the shared CUDA cache module
when NVIDIA support is configured.

## Work apps

Teams, Azure CLI, and Intune are disabled by default. Re-enable them in Home
Manager with:

```nix
local.work.microsoft.enable = true;
```

## Thunderbolt docks

Laptop dock support is shared through `profiles.nixos.laptop.default`. See:

```text
profiles/nixos/laptop/README.md
```

That profile enables `bolt` for Thunderbolt authorization and `fwupd` for
firmware updates. For a Lenovo ThinkPad Thunderbolt 4 Dock, start with:

```bash
boltctl list
sudo boltctl authorize <uuid>
sudo boltctl enroll <uuid>
nmcli device status
```

## After first boot

```bash
ssh deadbeef@192.168.1.151
nixos-rebuild switch --impure --flake path:/home/deadbeef/github/nixos#l-werk
sbctl status
systemd-cryptenroll /dev/nvme0n1p4
systemd-cryptenroll /dev/nvme0n1p3
```

Replace the temporary passwords and any placeholder SOPS values immediately.
