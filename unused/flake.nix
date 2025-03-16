{
  description = "A SecureBoot-enabled NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
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

  outputs = { self, nixpkgs, nixpkgs-unstable, lanzaboote, home-manager, ...}: {
    nixosConfigurations = {
      l-werk = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit nixpkgs-unstable; };
        modules = [
          # This is not a complete NixOS configuration and you need to reference
          # your normal configuration here.
# ls /etc/nixos | grep 'nix$' | grep -v flake | grep -v 'secboot\|nvidia' | sed 's/^/.\//g'    [16:35:26]
          ./audio-and-bluetooth.nix
          ./fonts.nix
          ./autologin.nix
          ./autoupdate.nix
          ./bootloader.nix
          ./desktop-environment.nix
          ./secondary-harddisk.nix
          ./nvidia.nix
          ./gc.nix
          ./hardware-configuration.nix
          ./locale-settings.nix
          ./network-basics.nix
          ./packages-and-applications.nix
          ./shell-env.nix
          ./users-and-groups.nix
          ./virtualization-general.nix
          ./virtualization-lxc.nix
          ./system-version.nix
          ./bootloader2.nix
          lanzaboote.nixosModules.lanzaboote

          home-manager.nixosModules.home-manager
          ./home-manager/home.nix

        ];
      };
    };

    packages.x86_64-linux = {
      default = self.nixosConfigurations.nixos.config.system.build.toplevel;
      nixos-rebuild = self.nixosConfigurations.nixos.config.system.build.toplevel;
    };
  };
}
