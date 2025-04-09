

This works (ignores .git):
```bash
vim /etc/nixos/flake.nix; nixos-rebuild switch --impure --flake path:/etc/nixos#l-werk
```

This also works:
```bash
$ cat ~/.config/nix/nix.conf
extra-experimental-features = nix-command flakes
access-tokens = github.com=ghp_......

# make it the same...
# update the respitory with nixos:
nix flake update --flake github:esp0xdeadbeef/nixos
# Then update with:
nixos-rebuild switch --no-write-lock-file --impure --flake "github:esp0xdeadbeef/nixos#$(hostname)"

```




# some testing with nixos on x13s

```
mount /dev/nvme0n1p2 /mnt
mount /dev/nvme0n1p1 /mnt/boot

(cd /mnt/ && rm -r ./cdrom ./dev ./home ./lib ./lib64 ./lost+found ./media ./mnt ./opt ./proc ./root ./run ./sbin ./snap ./srv ./swap.img ./sys ./tmp ./tmp.* ./usr ./var)
```

```bash
mkdir -p /mnt/etc/nixos/
vim /mnt/etc/nixos/flake.nix
```

```nix
{
  inputs = {
    #nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-x13s.url = "github:BrainWart/x13s-nixos";
  };

  #outputs =
  #  { ... }@inputs:
  #  {
  outputs = { nixpkgs, nixos-x13s, ... }@inputs: {
      nixosConfigurations.example = inputs.nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          inputs.nixos-x13s.nixosModules.default
          ({ config, pkgs, ... }: {
            nixos-x13s.enable = true;
            #nixos-x13s.kernel = "jhovold"; # jhovold is default, but mainline supported
            nixos-x13s.bluetoothMac = "E9:1C:3B:F0:FD:8C";  # Example MAC address
            nixos-x13s.wifiMac = "8c:fd:f0:1c:3b:0a";

            # install multiple kernels! note this increases eval time for each specialization
            specialisation = {
              # note that activation of each specialization is required to copy the dtb to the EFI, and thus boot
              mainline.configuration.nixos-x13s.kernel = "mainline";
            };

            # allow unfree firmware
            nixpkgs.config.allowUnfree = true;

            # define your fileSystems
            fileSystems."/".device = "/dev/nvme0n1p2";
            system.stateVersion = "24.11";
            services.openssh.enable = true;

            environment.systemPackages = with pkgs; [
              util-linux
            ];


          })
        ];
      };
    };
}
```

This will boot after installing:

```bash
nix --extra-experimental-features 'nix-command flakes' run github:NixOS/nixpkgs/nixos-24.11#nixos-install -- --impure --flake /mnt/etc/nixos#example && systemctl reboot -i
```

update the system will not fail i guess :D:

```bash
nixos-rebuild switch --flake /etc/nixos#example
```


```
# l-werk libvirtd, commit:
# Dead
# e0efcc4e9c6824881a7a428504120fb961ebe274
# Works:
# 65208e8043d59493cbf5adcb9ab346291a07fe3d
git diff 65208e8043d59493cbf5adcb9ab346291a07fe3d e0efcc4e9c6824881a7a428504120fb961ebe274
```

# wifi hotspot via nix os


https://discourse.nixos.org/t/nixos-access-point-via-hostapd/1060/3

