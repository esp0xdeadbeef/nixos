
# Before setting up

```bash
sed -i 's|/home/deadbeef/github/nixos/nixos/virtual-machine/dedicated-vm/codex-jail/|<your-new-path>|g' /home/deadbeef/github/nixos/nixos/virtual-machine/dedicated-vm/codex-jail/virtual-machine/dedicated-vm/codex-jail/README.md
sed -i 's/192.168.1.164/<your-new-ip>/g' /home/deadbeef/github/nixos/nixos/virtual-machine/dedicated-vm/codex-jail/README.md
```


# Setup the disks like this:


```bash
# host that contain the nixos configuration:
rsync -va /home/deadbeef/github/nixos nixos@192.168.1.164:~/github/
```

```bash
# inside the vm:
PATH_TO_DISKO="/home/nixos/github/nixos/nixos/virtual-machine/dedicated-vm/codex-jail/disko.nix"
head -c 512 /dev/urandom > /tmp/disk.key
#sed "s|/dev/sda|$(fdisk -l | grep '3.64 TiB' | cut -d ' ' -f 2 | tr -d ':')|g" $PATH_TO_DISKO -i
sed "s|/dev/sda|/dev/vda|g" $PATH_TO_DISKO -i
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode destroy,format,mount $PATH_TO_DISKO
cryptsetup luksAddKey /dev/disk/by-partlabel/disk-vda-luks -d /tmp/disk.key
# generate the hardware configuration
nixos-generate-config --root /mnt/
```


## to make sure the sops is installed correctly:

```bash
[ -f /$HOME/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N "" -f $HOME/.ssh/id_ed25519 -q
mkdir -p $HOME/.config/sops/age
nix-shell -p ssh-to-age --run 'bash -c "ssh-to-age -private-key -i $HOME/.ssh/id_ed25519 > $HOME/.config/sops/age/keys.txt"'

[ -d /mnt ] || echo "mount /mnt first"
[ -f /mnt/persist/$HOME/.ssh/id_ed25519 ] || ( mkdir /mnt/persist/$HOME/.ssh ; ssh-keygen -t ed25519 -N "" -f /mnt/persist/$HOME/.ssh/id_ed25519 -q)
mkdir -p /mnt/persist/$HOME/.config/sops/age
nix-shell -p ssh-to-age --run 'bash -c "ssh-to-age -private-key -i /mnt/persist/$HOME/.ssh/id_ed25519 > /mnt/persist/$HOME/.config/sops/age/keys.txt"'

key=$(nix-shell -p age --run "age-keygen -y /mnt/persist/$HOME/.config/sops/age/keys.txt")
echo -e "public key:\n$key"
```

And add the key to the ~/github/nixos/secrets/.sops.yaml

Run afterwards:
```bash
(cd ~/github/nixos/secrets/ ; sops updatekeys codex-jail.yaml)
```

# Resync the sops files

```bash
# rsync everything back from the host that contains the configs to the vm:
rsync -va /home/deadbeef/github/nixos nixos@192.168.1.164:~/github/
```

# Installing the vm:

```bash
nix --extra-experimental-features 'nix-command flakes' run github:NixOS/nixpkgs/nixos-25.11#nixos-install -- --impure --flake path:/home/nixos/github/nixos#codex-jail
reboot
```
