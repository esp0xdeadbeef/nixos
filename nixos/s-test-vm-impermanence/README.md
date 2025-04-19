


# Setup the disks like this:


```bash
# host that contain the nixos configuration:
rsync -va /home/deadbeef/github/nixos nixos@192.168.1.109:~/github/
```

```bash
# inside the vm:
PATH_TO_DISKO="/home/nixos/github/nixos/nixos/s-test-vm-impermanence/disko/build_disko.nix"
head -c 512 /dev/urandom > /tmp/disk.key
# sed -i 's/\/dev\/sda/<your-disk-to-format>/g' $PATH_TO_DISKO
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode destroy,format,mount $PATH_TO_DISKO
cryptsetup luksAddKey /dev/disk/by-partlabel/disk-vda-luks -d /tmp/disk.key
```

To sign the keys:
```bash
nix-shell -p sbctl --run 'sbctl create-keys'
mkdir /mnt/persist/etc/secureboot/ -p
cp /etc/secureboot/* /mnt/persist/etc/secureboot/ -r

# generate keys that proxmox bios understands:
nix-shell -p openssl --run 'openssl x509 -outform der -in /etc/secureboot/keys/PK/PK.pem -out /mnt/boot/PK.cer'
nix-shell -p openssl --run 'openssl x509 -outform der -in /etc/secureboot/keys/KEK/KEK.pem -out /mnt/boot/KEK.cer'
nix-shell -p openssl --run 'openssl x509 -outform der -in /etc/secureboot/keys/db/db.pem -out /mnt/boot/db.cer'
```


# Generate the hardware configuration

```bash
# inside the vm:
nixos-generate-config --root /mnt/
```

```bash
# host that contain the nixos configuration:
rsync -va nixos@192.168.1.109:/mnt/etc/nixos/hardware-configuration.nix /home/deadbeef/github/nixos/nixos/s-test-vm-impermanence/hardware/hardware-configuration.nix
```

```bash
# rsync everything back from the host that contains the configs to the vm:
rsync -va /home/deadbeef/github/nixos nixos@192.168.1.109:~/github/
```

# Installing the vm:

```bash
nix --extra-experimental-features 'nix-command flakes' run github:NixOS/nixpkgs/nixos-24.11#nixos-install -- --impure --flake path:/home/nixos/github/nixos#s-test-vm-impermanence
```

```bash
# setting root password...
# New password: 
# Retype new password: 
# passwd: password updated successfully
# installation finished!
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+12 --wipe-slot=tpm2 /dev/sda3
# 🔐 Please enter current passphrase for disk /dev/sda3: •                       
# New TPM2 token enrolled as key slot 2.
nix-shell -p sbctl --run 'sbctl status'
# Installed:      ✓ sbctl is installed
# Owner GUID:     fbbe9b29-dbf3-4044-a5fa-73def0a822f5
# Setup Mode:     ✓ Disabled
# Secure Boot:    ✗ Disabled
# Vendor Keys:    microsoft 
ls /mnt/boot/
# db.cer  EFI  KEK.cer  loader  PK.cer

# add them to the bios (boot into the firmware) -> secureboot -> add PK KEK db cer files from the first entry (boot directory)
reboot
```

# reboot the machine and enable sec boot:



# Setup the environment so it is using safeboot

```bash
# check if you're enrolled:
nix-shell -p sbctl --run 'sbctl status'
# Installed:	✓ sbctl is installed
# Owner GUID:	839f409d-60b2-458a-8524-80ee6aa9a295
# Setup Mode:	✓ Disabled
# Secure Boot:	✓ Enabled
# Vendor Keys:	none

sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+12 --wipe-slot=tpm2 /dev/sda3
```


# switch to a different config


```bash
nixos-rebuild switch --impure --flake path:/home/deadbeef/github/nixos#$(hostname)
```

