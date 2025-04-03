{
  description = "A optionally SecureBoot-enabled NixOS configuration";

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
      mkNixOS = hostname: hardwareModules: extraModules: secureBoot: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit nixpkgs-unstable hostname; };
        modules = nixpkgs.lib.filter (module: module != null) [
          # This is not a complete NixOS configuration and you need to reference
          # your normal configuration here.
          # ls /etc/nixos | grep 'nix$' | grep -v flake | grep -v 'secboot\|nvidia' | sed 's/^/.\//g'
          

          #./hardware/usb-firewall.nix
          ./desktop/users-and-groups.nix
          ./system/version.nix
          ./system/autoupdate.nix
          (if secureBoot then lanzaboote.nixosModules.lanzaboote else null)
          home-manager.nixosModules.home-manager
          #./home-manager/home-manager-module.nix
          ./home-manager/home.nix
        ]
          ++ hardwareModules # Hardware-specific modules
          ++ extraModules; # Additional per-machine modules
      };
    in {
      nixosConfigurations = {
        # Default config (no hardware, just the base system)
        default = mkNixOS "default" [] [] false;

        # Work laptop with NVIDIA
        l-werk = mkNixOS "l-werk" [
          ./hardware/l-werk/hardware-configuration.nix
          ./hardware/l-werk/audio-and-bluetooth.nix
          ./hardware/l-werk/sound-fix-l-werk.nix
          ./hardware/l-werk/nvidia-l-werk.nix
          ./hardware/l-werk/secondary-harddisk-l-werk.nix
          ./hardware/l-werk/bootloader.nix
          #./hardware/usb-firewall.nix
        ] [

          ./desktop/fonts.nix
          ./system/autologin.nix
          ./desktop/environment.nix
          ./system/garbage-collection.nix
          ./system/locale.nix
          ./network/basic.nix
          ./desktop/packages.nix
          ./desktop/darkmode.nix
          ./desktop/shell-env.nix
          ./virtualization/general.nix
          ./virtualization/lxc.nix
        ] true;

        # Private laptop with AMD GPU and other differences
        l-esp = mkNixOS "l-esp" [
          #./hardware-configuration-private.nix
          #./hardware/amd.nix
        ] [
          #./hardware/l-esp/hardware-configuration.nix
          {
             networking.hostName = "s-router-vpn-1";
          }
        ] true;
        s-router-vpn-1 = mkNixOS "s-router-vpn-1" [
          # configuration without secureboot and or lanzaboote
          ./hardware/s-router-vpn-1/hardware-configuration.nix
        ] [
          ./hardware/s-router-vpn-1/ssh-vim-and-basics.nix
          {
             networking.hostName = "s-router-vpn-1";
          }
          #./network/private-setup.nix
          #./desktop/private-config.nix
        ] false;
      };

      packages.x86_64-linux = {
        default = self.nixosConfigurations.default.config.system.build.toplevel;
      };
    };
}

