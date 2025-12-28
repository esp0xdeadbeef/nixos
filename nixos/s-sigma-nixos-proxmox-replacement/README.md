
This is going to be the replacement server of my currently running proxmox server.

This server needs to be emulated at this moment, because I'm having restrictions with my router configurations, which i want to have first tested, in a lab / semi prod env.

# Before setting up

1. use the gnome iso (vim installed by default)
2. disable sec boot for the setup (otherwise you can not find the iso / image)
3. sed this file with the ip and path to this file like so (so the documentation will be easier to read):

```bash
sed -i 's|/home/deadbeef/github/nixos|<your-new-path>|g' /home/deadbeef/github/nixos/nixos/s-sigma-nixos-proxmox-replacement/README.md
sed -i 's/192.168.1.184/<your-new-ip>/g' /home/deadbeef/github/nixos/nixos/s-sigma-nixos-proxmox-replacement/README.md
```


# Setup the disks like this:


```bash
# host that contain the nixos configuration:
rsync -va /home/deadbeef/github/nixos nixos@192.168.1.184:~/github/
```

```bash
# inside the vm:
ssh nixos@192.168.1.184
sudo -i
PATH_TO_DISKO="/home/nixos/github/nixos/nixos/s-sigma-nixos-proxmox-replacement/disko/build_disko.nix"
head -c 512 /dev/urandom > /tmp/disk.key
# sed -i 's/\/dev\/sda/<your-disk-to-format>/g' $PATH_TO_DISKO
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode destroy,format,mount $PATH_TO_DISKO
cryptsetup luksAddKey /dev/disk/by-partlabel/disk-vda-luks -d /tmp/disk.key
# generate the hardware configuration
nixos-generate-config --root /mnt/
```

To sign the keys:
```bash
nix-shell -p sbctl --run 'sbctl create-keys'


# only need to do this if you're not using MS products, and want to wipe all the EFI keys:
mkdir /mnt/persist/etc/secureboot/ -p
cp /etc/secureboot/* /mnt/persist/etc/secureboot/ -r

# generate keys that proxmox bios understands:
nix-shell -p openssl --run 'openssl x509 -outform der -in /etc/secureboot/keys/PK/PK.pem -out /mnt/boot/PK.cer'
nix-shell -p openssl --run 'openssl x509 -outform der -in /etc/secureboot/keys/KEK/KEK.pem -out /mnt/boot/KEK.cer'
nix-shell -p openssl --run 'openssl x509 -outform der -in /etc/secureboot/keys/db/db.pem -out /mnt/boot/db.cer'

```


# Generate the hardware configuration

```bash
# host that contain the nixos configuration:
rsync -va nixos@192.168.1.184:/mnt/etc/nixos/hardware-configuration.nix /home/deadbeef/github/nixos/nixos/s-sigma-nixos-proxmox-replacement/hardware/hardware-configuration.nix
```

```bash
# rsync everything back from the host that contains the configs to the vm:
rsync -va /home/deadbeef/github/nixos nixos@192.168.1.184:~/github/
```

# Installing the vm:

```bash
nix --extra-experimental-features 'nix-command flakes' run github:NixOS/nixpkgs/nixos-25.11#nixos-install -- --impure --flake path:/home/nixos/github/nixos#s-sigma-nixos-proxmox-replacement
# .....
# setting root password...
# New password: 
# Retype new password: 
# passwd: password updated successfully
# installation finished!

# I think this is bad, tpm is cleared already to run the installation media:
# previously i always rebooted here.
nix-shell -p sbctl --run 'sbctl enroll-keys -m'
# now reboot:
reboot
# no tricks with sec boot now, we only need to sign in with our new luks password.
```

```bash
# so we will first do this:
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+12 --wipe-slot=tpm2 /dev/sda3
# 🔐 Please enter current passphrase for disk /dev/sda3: •                       
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
rsync -va /home/deadbeef/github/nixos deadbeef@192.168.1.184:~/github/
nixos-rebuild switch --impure --flake path:/home/deadbeef/github/nixos#$(hostname)
nixos-rebuild boot --impure --flake path:/home/deadbeef/github/nixos#$(hostname) && sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+12 --wipe-slot=tpm2 /dev/sda3 && reboot
```

