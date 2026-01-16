
# VM Orchestration Design Specification

This repository defines the design and operational model for managing virtual machines using a **NAS-centric control plane**.

The authoritative system state is stored on the NAS. All hypervisors and orchestration components derive their behavior from this shared state. VM lifecycle, placement, and recovery are driven by declarative data rather than local configuration.

The orchestration model is inspired by **ISA-88 / PackML**, applying its state-machine principles to infrastructure management. Each component (coordinator, host, VM) follows an explicit and well-defined lifecycle with deterministic transitions.

## Structure

* `./orchestrator/`  
    Contains the conceptual and logical design of the orchestration system, including:
    
    * State machines for coordinators, hosts, and virtual machines
        
    * Interaction rules and control flow
        
    * Expected filesystem layout and ownership of state
        
    * Failure handling and recovery semantics
        

## Design Principles

* **NAS as source of truth**  
    All authoritative state is stored on the NAS. Local state is ephemeral and reconstructible.
    
* **Deterministic behavior**  
    Every component operates as a finite state machine with explicit transitions.
    
* **Decoupled orchestration**  
    Hosts do not coordinate directly with each other; all coordination flows through shared state.
    
* **Declarative intent, imperative execution**  
    Desired state is declared in the filesystem; agents reconcile actual state accordingly.
    
* **Predictable recovery**  
    Power loss, host failure, or network interruptions converge to a known-safe state.
    

This repository focuses on _design correctness and clarity_, not implementation convenience.

# Current state

This is going to be the replacement server of my currently running proxmox server.

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
mkdir -p /persist
mount --bind /mnt/persist /persist
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

mkdir -p /persist/etc/secureboot/
cp -r /mnt/persist/var/lib/sbctl/* /persist/etc/secureboot/
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

# Setup Clevis/Tang Auto-Decrypt

Auto-decrypt LUKS via Tang server - no password at boot.

## Generate JWE on the target machine

```bash
ssh nixos@192.168.1.150
sudo -i
cd /home/deadbeef/github/nixos/nixos/s-sigma/hardware/disks/ 
./clevis-init-jwe.sh # you will be prompted for your luks password
```

Output should look like this:

```bash
./clevis-init-jwe.sh
Enter any existing passphrase:
The advertisement contains the following signing keys:

<redacted>

Do you wish to trust these keys? [ynYN] y
✅ works
JWE created at /tmp/nvme0n1p1.jwe
```


```bash
# host that contains the nixos configuration:
rsync -va nixos@192.168.1.150:/tmp/nvme0n1p1.jwe /home/deadbeef/github/nixos/nixos/s-sigma/hardware/disks/nvme0n1p1.jwe
rsync -va nixos@192.168.1.150:/tmp/nvme0n1p1.jwe /home/deadbeef/github/nixos/nixos/s-sigma/hardware/disks/nvme0n1p1.jwe
```

```bash
rsync -va /home/deadbeef/github/nixos nixos@192.168.1.150:~/github/
```

## Security Note

JWE is safe in public repo - only decryptable via your LAN Tang server.

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

# MAKE SURE YOU READ THE /home/deabeef/github/nixos/secrets/ DIRECTORY, you need to get the PUBLIC sops key, and update the `sops edit ./s-sigma-root.yaml`

# now reboot:
reboot
# no tricks with sec boot now, we only need to sign in with our new luks password.
```
