
This is going to be the replacement server of my currently running proxmox server.

This server needs to be emulated at this moment, because I'm having restrictions with my router configurations, which i want to have first tested, in a lab / semi prod env.





# !!!!! before fysical setup !!!!!
Before you begin with the fysical setup, MAKE SURE YOU EDIT THE MGMT interface!


# Before setting up

1. use the gnome iso (vim installed by default)
2. disable sec boot for the setup (otherwise you can not find the iso / image)
3. sed this file with the ip and path to this file like so (so the documentation will be easier to read):

```bash
sed -i 's|/home/deadbeef/github/nixos|<your-new-path>|g' /home/deadbeef/github/nixos/nixos/s-sigma/README.md
sed -i 's/192.168.1.150/<your-new-ip>/g' /home/deadbeef/github/nixos/nixos/s-sigma/README.md
```


# Setup the disks like this:


```bash
# host that contain the nixos configuration:
rsync -va /home/deadbeef/github/nixos nixos@192.168.1.150:~/github/
```

```bash
# inside the vm:
ssh nixos@192.168.1.150
sudo -i
PATH_TO_DISKO="/home/nixos/github/nixos/nixos/s-sigma/disko/build_disko.nix"
PATH_TO_DISKO="/home/nixos/github/nixos/nixos/s-sigma/build_disko/build_disko.nix"
head -c 512 /dev/urandom > /tmp/disk.key
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode destroy,format,mount $PATH_TO_DISKO
cryptsetup luksAddKey /dev/disk/by-partlabel/disk-vda-luks -d /tmp/disk.key
# generate the hardware configuration
nixos-generate-config --root /mnt/
# mkdir the persist directory on the nvme disk:
mkdir -p /mnt/persist
mount --bind /persist /mnt/persist
```

To sign the keys:
```bash
# only need to do this if you're not using MS products, and want to wipe all the EFI keys:
nix-shell -p sbctl --run 'sbctl create-keys'
mkdir -p /mnt/persist/var/lib/sbctl
cp -r /var/lib/sbctl/* /mnt/persist/var/lib/sbctl


# generate keys that proxmox bios understands:
nix-shell -p openssl --run 'openssl x509 -outform der -in /mnt/persist/var/lib/sbctl/keys/PK/PK.pem -out /mnt/boot/PK.cer'
nix-shell -p openssl --run 'openssl x509 -outform der -in /mnt/persist/var/lib/sbctl/keys/KEK/KEK.pem -out /mnt/boot/KEK.cer'
nix-shell -p openssl --run 'openssl x509 -outform der -in /mnt/persist/var/lib/sbctl/keys/db/db.pem -out /mnt/boot/db.cer'

cp -r /mnt/persist/var/lib/sbctl/* /persist/etc/secureboot/

# BELOW NOT NEEDED, AND DOESN'T WORK, JUST IGNORE ERRORS IN -> MALLICIOUS -> CONTINUE ON ERRORS DONT PROMPT FOR F1 / F2.
# 1. Download Microsoft certificates from reliable sources:
nix-shell -p wget --run '
  # Windows Production PCA 2011 (base64 format from GitHub)
  wget -O /tmp/ms.pem https://raw.githubusercontent.com/microsoft/msix-packaging/master/resources/certs/base64_Windows_Production_PCA_2011.cer

  # Microsoft Corporation UEFI CA 2011 (from Microsoft's Secure Boot Objects)
  wget -O /tmp/ms2.der https://uefipkisrevoked.blob.core.windows.net/replacedcerts/MicCorUEFCA2011_2011-06-27.crt
  openssl x509 -inform der -in /tmp/ms2.der -out /tmp/ms2.pem
'

# 2. Combine with your db certificate:
nix-shell -p openssl --run '
  cat /mnt/persist/var/lib/sbctl/keys/db/db.pem /tmp/ms.pem /tmp/ms2.pem > /tmp/combined-db.pem
  cp /tmp/combined-db.pem /mnt/persist/var/lib/sbctl/keys/db/db.pem

  # Regenerate the DER certificate for BIOS import
  openssl x509 -outform der -in /mnt/persist/var/lib/sbctl/keys/db/db.pem -out /mnt/boot/db.cer
'

# 3. Sign your boot files with the updated key:
nix-shell -p sbsigntool --run '
  sbsign --key /mnt/persist/var/lib/sbctl/keys/db/db.key \
         --cert /mnt/persist/var/lib/sbctl/keys/db/db.pem \
         --output /mnt/boot/EFI/nixos/kernel.efi \
         /mnt/boot/EFI/nixos/kernel.efi

  sbsign --key /mnt/persist/var/lib/sbctl/keys/db/db.key \
         --cert /mnt/persist/var/lib/sbctl/keys/db/db.pem \
         --output /mnt/boot/EFI/nixos/grubx64.efi \
         /mnt/boot/EFI/nixos/grubx64.efi
'
```


# Generate the hardware configuration

```bash
# host that contain the nixos configuration:
rsync -va nixos@192.168.1.150:/mnt/etc/nixos/hardware-configuration.nix /home/deadbeef/github/nixos/nixos/s-sigma/hardware/hardware-configuration.nix
```

```bash
# rsync everything back from the host that contains the configs to the vm:
rsync -va /home/deadbeef/github/nixos nixos@192.168.1.150:~/github/
```
# installing sops:

```bash
[ -d /mnt ] || echo "mount /mnt first"
[ -f /mnt/persist/$HOME/.ssh/id_ed25519 ] || ( mkdir /mnt/persist/$HOME/.ssh ; ssh-keygen -t ed25519 -N "" -f /mnt/persist/$HOME/.ssh/id_ed25519 -q)
mkdir -p /mnt/persist/$HOME/.config/sops/age
nix-shell -p ssh-to-age --run 'bash -c "ssh-to-age -private-key -i /mnt/persist/$HOME/.ssh/id_ed25519 > /mnt/persist/$HOME/.config/sops/age/keys.txt"'

key=$(nix-shell -p age --run "age-keygen -y /mnt/persist/$HOME/.config/sops/age/keys.txt")
echo -e "public key:\n$key"
# age1y0m2kr2n9ejp7q9u80lgtl6fdcddm8t0nz2fhtxtxdkpps0u4dcqhk8pm0

```

Add it to the secrets (.sops.yaml, read the readme (also update the keys related to this machine)).

```bash
# sops updatekeys s-sigma-root.yaml
```

```bash
sops updatekeys s-sigma-root.yaml
2025/12/30 19:39:08 Syncing keys for file /home/deadbeef/github/nixos/secrets/s-sigma-root.yaml
The following changes will be made to the file's groups:
Group 1
    age1057zl675g0wv59dvzylsu59a35dnv8sc4m8545avl60u5uvdrfpqhjp256
    age1vfresmphe0ahyn9vdtsqzzz72kt2lyd8nya376yk7yxjpc5p298qya76kz
+++ age1evz7q5h6hqwgs5apscnehvn9jcf4tsl02tqak0xkyx702rxzcdlq3l5zgg
--- age10kx7f6ztc75kw0h4k05nyqh2hu637w3ktkr74eds43tfje5jzqrsjlpaz7
Is this okay? (y/n):y
2025/12/30 19:39:10 File /home/deadbeef/github/nixos/secrets/s-sigma-root.yaml synced with new keys
```


```bash
rsync -va /home/deadbeef/github/nixos nixos@192.168.1.150:~/github/
```

# Installing the vm:

```bash
nix --extra-experimental-features 'nix-command flakes' run github:NixOS/nixpkgs/nixos-25.11#nixos-install -- --impure --flake path:/home/nixos/github/nixos#s-sigma
# .....
# setting root password...
# New password: 
# Retype new password: 
# passwd: password updated successfully
# installation finished!

# previously i always rebooted here, but sign first (sec boot is in setup mode / disabled / wiped, otherwise you can not boot into the iso.)
nix-shell -p sbctl --run 'sbctl enroll-keys -m'

# MAKE SURE YOU READ THE /home/deabeef/github/nixos/secrets/ DIRECTORY, you need to get the PUBLIC sops key, and update the ``

# now reboot:
reboot
# no tricks with sec boot now, we only need to sign in with our new luks password.
```

```bash
# so we will first do this:
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+12 --wipe-slot=tpm2 /dev/sda3
# 🔐 Please enter current passphrase for disk /dev/sda3: 
# New TPM2 token enrolled as key slot 2.
# we can not do the next step because:
ls /mnt/boot/
# db.cer  EFI  KEK.cer  loader  PK.cer

# if the output is like this we can enroll the keys:
nix-shell -p sbctl --run 'sbctl status'
# Installed:      ✓ sbctl is installed
# Owner GUID:     c48257e4-f5b8-447a-9ae9-c78aae5e7021
# Setup Mode:     ✗ Enabled
# Secure Boot:    ✗ Disabled
# Vendor Keys:    none


# with microsoft:
nix-shell -p sbctl --run 'sbctl enroll-keys -m'
# Enrolling keys to EFI variables...
# With vendor keys from microsoft...✓ 
# Enrolled keys to the EFI variables!
nix-shell -p sbctl --run 'sbctl status'
# Installed:      ✓ sbctl is installed
# Owner GUID:     c48257e4-f5b8-447a-9ae9-c78aae5e7021
# Setup Mode:     ✓ Disabled
# Secure Boot:    ✗ Disabled
# Vendor Keys:    microsoft

# without microsoft (read the wiki - know what you're doing - https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot):
nix-shell -p sbctl --run 'sbctl enroll-keys'

# add them to the bios (boot into the firmware) -> secureboot -> add PK KEK db cer files from the first entry (boot directory)
reboot
```

# Setup the environment so it is using safeboot

```bash


# check if you're enrolled:
nix-shell -p sbctl --run 'sbctl status'
# Installed:	✓ sbctl is installed
# Owner GUID:	839f409d-60b2-458a-8524-80ee6aa9a295
# Setup Mode:	✓ Disabled
# Secure Boot:	✓ Enabled
# Vendor Keys:	none


# use this setting on fysical devices (7 is important here):
# doesn't look like applicable to us, this works for me 
# https://superuser.com/questions/1640985/how-to-enable-bitlocker-when-booting-windows-10-from-a-non-microsoft-boot-manage
# It still works for me though in a qemu image on proxmox:
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+12 --wipe-slot=tpm2 /dev/sda3
```


# Switch to a different config


```bash
# deadbeef i my user (ssh) don't worry about the eavedropping error in ssh, to get rid of the errors, rm the last two LINES of the `~/.ssh/known_hosts` of your host, then do a rsync:
rsync -va /home/deadbeef/github/nixos deadbeef@192.168.1.150:~/github/
nixos-rebuild switch --impure --flake path:/home/deadbeef/github/nixos#$(hostname)
nixos-rebuild boot --impure --flake path:/home/deadbeef/github/nixos#$(hostname) && sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+12 --wipe-slot=tpm2 /dev/sda3 && reboot
```

