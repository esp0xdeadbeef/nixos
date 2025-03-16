{
  description = "A SecureBoot-enabled NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    #nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";

      # Optional but recommended to limit the size of your system closure.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Add Home Manager as an input
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, lanzaboote, home-manager, ... }:
    let
      mkNixOS = hostname: hardwareModules: extraModules: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit nixpkgs-unstable hostname; };
        modules = [
          # This is not a complete NixOS configuration and you need to reference
          # your normal configuration here.
# ls /etc/nixos | grep 'nix$' | grep -v flake | grep -v 'secboot\|nvidia' | sed 's/^/.\//g'    [16:35:26]
          ./hardware/audio-and-bluetooth.nix
          ./desktop/fonts.nix
          ./system/autologin.nix
          ./system/autoupdate.nix
          ./system/bootloader.nix
          ./desktop/environment.nix
          ./system/garbage-collection.nix
          ./system/locale.nix
          ./network/basic.nix
          ./desktop/packages.nix
          ./desktop/darkmode.nix
          ./desktop/shell-env.nix
          ./desktop/users-and-groups.nix
          ./virtualization/general.nix
          ./virtualization/lxc.nix
          ./system/version.nix
          #./hardware/usb-firewall.nix
          lanzaboote.nixosModules.lanzaboote

          home-manager.nixosModules.home-manager
          ./home-manager/home.nix

        ] 
          ++ hardwareModules # Hardware-specific modules
          ++ extraModules; # Additional per-machine modules
      };
    in {
      nixosConfigurations = {
        # Default config (no hardware, just the base system)
        default = mkNixOS "default" [] [];

        # Work laptop with NVIDIA
        l-werk = mkNixOS "l-werk" [
          #./hardware-configuration.nix
          #./hardware/hardware-configuration-l-werk.nix
          ./hardware/hardware-configuration-l-werk.nix
          ./hardware/nvidia-l-werk.nix
          ./hardware/secondary-harddisk-l-werk.nix
          #./hardware/usb-firewall.nix
        ] [];

        # Private laptop with AMD GPU and other differences
        private = mkNixOS "l-esp" [
          #./hardware-configuration-private.nix
          #./hardware/amd.nix
        ] [
          #./network/private-setup.nix
          #./desktop/private-config.nix
        ];
      };

      packages.x86_64-linux = {
        default = self.nixosConfigurations.default.config.system.build.toplevel;
      };
    };
}
