
# Before setting up

1. use the gnome iso (vim installed by default)
2. disable sec boot for the setup (otherwise you can not find the iso / image)
3. sed this file with the ip and path to this file like so (so the documentation will be easier to read):

```bash
sed -i 's|/home/deadbeef/github/nixos|<your-new-path>|g' /home/deadbeef/github/nixos/nixos/l-werk/README.md
sed -i 's/192.168.1.165/<your-new-ip>/g' /home/deadbeef/github/nixos/nixos/l-werk/README.md
```


# Setup the disks like this:


```bash
# host that contain the nixos configuration:
rsync -va /home/deadbeef/github/nixos nixos@192.168.1.165:~/github/
```

```bash
# inside the ssh session:
ssh nixos@192.168.1.165
sudo -i
PATH_TO_DISKO="/home/nixos/github/nixos/nixos/l-werk/disko/build_disko.nix"
head -c 512 /dev/urandom > /tmp/disk.key
sed -i 's|/dev/sda|/dev/nvme0n1|g' $PATH_TO_DISKO
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode destroy,format,mount $PATH_TO_DISKO
cryptsetup luksAddKey /dev/disk/by-partlabel/disk-vda-luks -d /tmp/disk.key
# generate the hardware configuration
nixos-generate-config --root /mnt/
```

To sign the keys:
```bash
nix-shell -p sbctl --run 'sbctl create-keys'


# only need to do this if you're not using MS products, and want to wipe all the EFI keys:
mkdir -p /mnt/persist/var/lib/sbctl
cp -r /var/lib/sbctl/* /mnt/persist/var/lib/sbctl


# generate keys that proxmox bios understands:
nix-shell -p openssl --run 'openssl x509 -outform der -in /mnt/persist/var/lib/sbctl/keys/PK/PK.pem -out /mnt/boot/PK.cer'
nix-shell -p openssl --run 'openssl x509 -outform der -in /mnt/persist/var/lib/sbctl/keys/KEK/KEK.pem -out /mnt/boot/KEK.cer'
nix-shell -p openssl --run 'openssl x509 -outform der -in /mnt/persist/var/lib/sbctl/keys/db/db.pem -out /mnt/boot/db.cer'

```


# Generate the hardware configuration

```bash
# host that contain the nixos configuration:
rsync -va nixos@192.168.1.165:/mnt/etc/nixos/hardware-configuration.nix /home/deadbeef/github/nixos/nixos/l-werk/hardware/hardware-configuration.nix
```

```bash
# rsync everything back from the host that contains the configs to the vm:
rsync -va /home/deadbeef/github/nixos nixos@192.168.1.165:~/github/
```

# Installing the vm:

```bash
nix --extra-experimental-features 'nix-command flakes' run github:NixOS/nixpkgs/nixos-24.11#nixos-install -- --impure --flake path:/home/nixos/github/nixos#l-werk
# .....
# setting root password...
# New password: 
# Retype new password: 
# passwd: password updated successfully
# installation finished!
# reboot now, we can not setup the tpm, because the driver is not loaded in the live env and we are not in sec mode
reboot
# change the settings in your bios to secure boot, delete the PK keys, add the new keys generated in /boot/ (one by one.)
```

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+12 --wipe-slot=tpm2 /dev/nvme0n1p3
# 🔐 Please enter current passphrase for disk /dev/sda3: •                       
# New TPM2 token enrolled as key slot 2.
# we can not do the next step because:
ls /boot/
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
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+12 --wipe-slot=tpm2 /dev/nvme0n1p3
```


# Switch to a different config


```bash
# deadbeef i my user (ssh) don't worry about the eavedropping error in ssh, to get rid of the errors, rm the last two LINES of the `~/.ssh/known_hosts` of your host, then do a rsync:
rsync -va /home/deadbeef/github/nixos deadbeef@192.168.1.165:~/github/
nixos-rebuild switch --impure --flake path:/home/deadbeef/github/nixos#$(hostname)
nixos-rebuild boot --impure --flake path:/home/deadbeef/github/nixos#$(hostname) && sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+12 --wipe-slot=tpm2 /dev/sda3 && reboot
```

# sops

Add the keys to /home/deadbeef/github/nixos/secrets/

```bash
~/nixos-switch.sh                                                                              1 ↵
building the system configuration...
Installing Lanzaboote to "/boot"...
Collecting garbage...
Successfully installed Lanzaboote.
activating the configuration...
generating machine-specific age key...
# created: 2025-09-06T03:57:35+02:00
# public key: age1l7dapm3z3w77hwvgrz6clnxzguchfp0qx997ddtv25fnrw8m6elsfsk35q
AGE-SECRET-KEY-redacted
sops-install-secrets: Imported /persist/etc/ssh/ssh_host_rsa_key as GPG key with fingerprint 0adf57b94141ea0eff10ed80a00a382bac2569db
sops-install-secrets: Imported /home/deadbeef/.ssh/id_ed25519 as age key with fingerprint age12ghkem2kyy89htjqd7fv7az34gg5g87zcdtzm0gq23tdll60avtsqsz7vk
/nix/store/ff49sadsyjzk6xqhn575rawv8qyc84y3-sops-install-secrets-0.0.1/bin/sops-install-secrets: failed to decrypt '/nix/store/3viv7d3zhjx9770xqfv3qzlqm956ihfd-l-werk-default.yaml': Error getting data key: 0 successful groups required, got 0
Activation script snippet 'setupSecretsForUsers' failed (1)
warning: password file ‘/run/secrets-for-users/deadbeef-passwd’ does not exist
setting up /etc...
warning: /root/.nix-defexpr/channels exists, but channels have been disabled.
warning: /nix/var/nix/profiles/per-user/root/channels exists, but channels have been disabled.
warning: /root/.nix-defexpr/channels exists, but channels have been disabled.
Due to https://github.com/NixOS/nix/issues/9574, Nix may still use these channels when NIX_PATH is unset.
Delete the above directory or directories to prevent this.
Failed to run activate script
reloading user units for gdm...
reloading user units for deadbeef...
restarting sysinit-reactivation.target
the following new units were started: libvirtd.service, NetworkManager-dispatcher.service, run-secrets\x2dfor\x2dusers.d.mount, sysinit-reactivation.target, systemd-tmpfiles-resetup.service
warning: the following units failed: home-manager-deadbeef.service
× home-manager-deadbeef.service - Home Manager environment for deadbeef
     Loaded: loaded (/etc/systemd/system/home-manager-deadbeef.service; enabled; preset: ignored)
     Active: failed (Result: exit-code) since Sat 2025-09-06 03:57:37 CEST; 270ms ago
 Invocation: 3a6939ac8ecb48daa893aaa98d0bf080
    Process: 28839 ExecStart=/nix/store/2bkpj12f380wh0dfci43s6dszikdracn-hm-setup-env /nix/store/apmw85amnh05jm6y2drwyp7x5pz0f0vp-home-manager-generation (code=exited, status=1/FAILURE)
   Main PID: 28839 (code=exited, status=1/FAILURE)
         IP: 0B in, 0B out
         IO: 4.7M read, 0B written
   Mem peak: 6.2M
        CPU: 245ms

sep 06 03:57:37 l-werk hm-activate-deadbeef[28839]: Activating reloadSystemd
sep 06 03:57:37 l-werk hm-activate-deadbeef[29174]: Starting units: sops-nix.service
sep 06 03:57:37 l-werk hm-activate-deadbeef[29174]: sops-nix.service failed
sep 06 03:57:37 l-werk hm-activate-deadbeef[28839]: Activating sops-nix
sep 06 03:57:37 l-werk systemctl[29211]: Job for sops-nix.service failed because the control process exited with error code.
sep 06 03:57:37 l-werk systemctl[29211]: See "systemctl --user status sops-nix.service" and "journalctl --user -xeu sops-nix.service" for details.
sep 06 03:57:37 l-werk systemd[1]: home-manager-deadbeef.service: Main process exited, code=exited, status=1/FAILURE
sep 06 03:57:37 l-werk systemd[1]: home-manager-deadbeef.service: Failed with result 'exit-code'.
sep 06 03:57:37 l-werk systemd[1]: Failed to start Home Manager environment for deadbeef.
sep 06 03:57:37 l-werk systemd[1]: home-manager-deadbeef.service: Consumed 245ms CPU time, 6.2M memory peak, 4.7M read from disk.
warning: error(s) occurred while switching to the new configuration
```
