{
  description = "A optionally SecureBoot-enabled NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    # nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";

      # Optional but recommended to limit the size of your system closure.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Add Home Manager as an input
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-x13s.url = "github:BrainWart/x13s-nixos";

    # widevine:
    nixos-aarch64-widevine.url = "github:epetousis/nixos-aarch64-widevine";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      lanzaboote,
      home-manager,
      nixos-x13s,
      nixos-aarch64-widevine,
      ...
    }:
    let
      mkNixOS =
        hostname: hardwareModules: extraModules: secureBoot:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit nixpkgs-unstable hostname; };
          modules =
            nixpkgs.lib.filter (module: module != null) [
              # This is not a complete NixOS configuration and you need to reference
              # your normal configuration here.
              # ls /etc/nixos | grep 'nix$' | grep -v flake | grep -v 'secboot\|nvidia' | sed 's/^/.\//g'

              #./hardware/usb-firewall.nix
              ./desktop/users-and-groups.nix
              ./system/version.nix
              ./system/autoupdate.nix

              home-manager.nixosModules.home-manager
              # ./home-manager/home-manager-module.nix
              # ./home-manager/home.nix
              
              {
                services.fwupd.enable = true;
              }
              (if secureBoot then lanzaboote.nixosModules.lanzaboote else null)
            ]
            ++ hardwareModules # Hardware-specific modules
            ++ extraModules; # Additional per-machine modules
        };
    in
    {
      nixosConfigurations = {
        # Default config (no hardware, just the base system)
        default = mkNixOS "default" [ ] [ ] false;

        # Work laptop with NVIDIA
        l-werk =
          mkNixOS "l-werk"
            [
              ./hardware/l-werk/hardware-configuration.nix
              ./hardware/l-werk/audio-and-bluetooth.nix
              ./hardware/l-werk/sound-fix-l-werk.nix
              ./hardware/l-werk/nvidia-l-werk.nix
              ./hardware/l-werk/secondary-harddisk-l-werk.nix
              ./hardware/l-werk/bootloader.nix
              #./hardware/usb-firewall.nix
            ]
            [
              ./llms/ollama.nix

              ./home-manager/l-werk/home.nix
              ./desktop/fonts.nix
              #./system/autologin.nix
              ./desktop/environment.nix
              ./system/garbage-collection.nix
              ./system/locale.nix
              ./network/hostname.nix
              ./network/firewall.nix
              ./network/nat-lxc.nix
              ./desktop/applets.nix
              ./desktop/packages.nix
              ./desktop/darkmode.nix
              ./desktop/shell-env.nix
              ./virtualization/general.nix
              ./virtualization/lxc.nix
              ./virtualization/libvirt.nix
              ./virtualization/podman.nix

              {
                environment.interactiveShellInit = ''
                  ZSH_THEME=clean
                '';
              }
            ]
            true;

        # Private laptop with AMD GPU and other differences
        l-esp =
          mkNixOS "l-esp"
            [
              ./hardware/l-esp/hardware-configuration.nix
              ./hardware/l-esp/bootloader.nix
              ./hardware/l-esp/amd.nix
              ./hardware/l-esp/swap-and-tmpfs.nix
              ./hardware/l-esp/audio-and-bluetooth.nix
              ./hardware/l-esp/secondary-harddisk.nix
            ]
            [
              ./home-manager/l-esp/home.nix
              # ./system/autologin.nix
              ./desktop/fonts.nix
              ./desktop/environment.nix
              ./system/garbage-collection.nix
              ./system/locale.nix
              ./network/hostname.nix
              ./network/firewall.nix
              ./network/nat-lxc.nix
              ./desktop/applets.nix
              ./desktop/packages.nix
              ./desktop/darkmode.nix
              ./desktop/shell-env.nix
              ./virtualization/general.nix
              ./virtualization/lxc.nix



              {
                networking.hostName = "l-esp";
                networking.networkmanager.enable = true;
                nixpkgs.config.allowUnfree = true;
                services.gnome.gnome-keyring.enable = true;
                services.desktopManager.plasma6.enable = true;
                programs.sway.enable = true;
                services.displayManager.defaultSession = "none+i3";
              }

              {
                environment.interactiveShellInit = ''
                  ZSH_THEME=robbyrussell
                '';
              }
            ]
            true;
        s-router-vpn-1 =
          mkNixOS "s-router-vpn-1"
            [
              # configuration without secureboot and or lanzaboote
              ./hardware/s-router-vpn-1/hardware-configuration.nix
            ]
            [
              ./hardware/s-router-vpn-1/ssh-vim-and-basics.nix
              {
                networking.hostName = "s-router-vpn-1";
                services.openssh.enable = true;
                networking.networkmanager.enable = true;
                services.xserver.enable = true;
                services.displayManager.sddm.enable = true;
                services.desktopManager.plasma6.enable = true;
              }
              #./network/private-setup.nix
              #./desktop/private-config.nix
            ]
            false;
        l-x13s = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            nixos-x13s.nixosModules.default
            ./hardware/l-x13s/hardware-configuration.nix
            {
              networking.hostName = "l-x13s";
            }
            ./desktop/fonts.nix
            # ./system/autologin.nix
            ./desktop/environment.nix
            ./system/garbage-collection.nix
            ./system/locale.nix
            # ./network/hostname.nix
            ./network/firewall.nix
            # ./network/nat-lxc.nix
            ./desktop/applets.nix
            # ./desktop/packages.nix
            ./desktop/darkmode.nix
            ./desktop/shell-env.nix
            ./desktop/users-and-groups.nix
            ./system/version.nix
            ./system/autoupdate.nix
            ./packages/l-x13s/packages.nix
            ./network/l-x13s/nmcli.nix
            {
              nixpkgs.overlays = [ nixos-aarch64-widevine.overlays.default ];
            }
            ./packages/l-x13s/widevine.nix
            {
              environment.interactiveShellInit = ''
                ZSH_THEME=trapd00r
              '';
            }
          ];
        };
      };

      packages.x86_64-linux = {
        #default = self.nixosConfigurations.default.config.system.build.toplevel;
      };
    };
}
