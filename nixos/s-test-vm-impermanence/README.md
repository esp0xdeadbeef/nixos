


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



# Setup the environment so it is using safeboot

If any changes has been made:

```
sudo sbctl create-keys
```

```bash
nixos-rebuild switch --impure --flake path:/home/deadbeef/github/nixos#$(hostname)
```
Sign the boot loader, and use the tpm to unlock:
```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+12 --wipe-slot=tpm2 /dev/sda3
```

