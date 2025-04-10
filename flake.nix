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
    impermanence.url = "github:nix-community/impermanence";

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
      impermanence,
      ...
    }:
    let
      lib = nixpkgs.lib;
        mkNixOS_import = import ./lib/mkNixOS.nix {
    inherit lib lanzaboote impermanence home-manager nixpkgs;
  };


      mkNixOS =
        system: hostname: hardwareModules: extraModules: secureBoot: isEphemeral:
        nixpkgs.lib.nixosSystem {
          inherit system;

          specialArgs = {
            inherit nixpkgs hostname;
            username = "deadbeef";
          };
          # specialArgs = { inherit nixpkgs-unstable hostname; };
          modules =
            nixpkgs.lib.filter (module: module != null) [
              ./desktop/users-and-groups.nix
              ./system/version.nix
              ./system/autoupdate.nix
              ./time/timezone.nix
              ./general/tooling.nix
              home-manager.nixosModules.home-manager
              # {
              #   specialArgs = {
              #     inherit nixpkgs-unstable hostname;
              #     username = "deadbeef";
              #   };
              # }
              impermanence.nixosModules.impermanence

              {
                services.fwupd.enable = true;
                nixpkgs.config.allowUnfree = true;
              }
              (if secureBoot then lanzaboote.nixosModules.lanzaboote else null)
            ]
            ++ hardwareModules
            ++ lib.optional isEphemeral ./modules/impermanence.nix
            ++ extraModules;

        };
    in
    {
      nixosConfigurations = {
        s-test-vm = import ./hosts/s-test-vm.nix { inherit mkNixOS_import; };

        
        # Default config (no hardware, just the base system)
        default = mkNixOS "x86_64-linux" "default" [ ] [ ] false false;

        # Work laptop with NVIDIA
        l-werk =
          mkNixOS "x86_64-linux" "l-werk"
            [
              ./hardware/l-werk/hardware-configuration.nix
              ./hardware/l-werk/audio-and-bluetooth.nix
              ./hardware/l-werk/sound-fix-l-werk.nix
              ./hardware/l-werk/nvidia-l-werk.nix
              ./hardware/l-werk/secondary-harddisk-l-werk.nix
              ./hardware/l-werk/bootloader.nix
              ./hardware/l-werk/swap-and-tmpfs.nix
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
            true # secure boot
            false # impermanence.nix
        ;

        # Private laptop with AMD GPU and other differences
        l-esp =
          mkNixOS "x86_64-linux" "l-esp"
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
              ./virtualization/libvirt.nix
              ./virtualization/podman.nix

              {
                networking.hostName = "l-esp";
                networking.networkmanager.enable = true;
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
            true # secure boot
            false # impermanence.nix
        ;
        # s-test-vm = import ./hosts/s-test-vm.nix { inherit mkNixOS_import; };
        s-router-vpn-1 =
          mkNixOS "x86_64-linux" "s-router-vpn-1"
            [
              # configuration without secureboot and or lanzaboote
              ./hardware/s-router-vpn-1/hardware-configuration.nix
              ./hardware/is-vm/qemu-guest.nix
              ./network/router/management-network.nix
              ./network/router/vlan-configuration-phys0.nix

            ]
            [
              ./hardware/s-router-vpn-1/ssh-vim-and-basics.nix
              ./desktop/shell-env.nix
              {
                networking.hostName = "s-router-vpn-1";
                services.openssh.enable = true;
                services.xserver.enable = true;
                services.displayManager.sddm.enable = true;
                services.desktopManager.plasma6.enable = true;
                boot.loader.grub.configurationLimit = 15;
                environment.interactiveShellInit = ''
                  ZSH_THEME=agnoster
                '';

                security.sudo.enable = true;
                security.sudo.extraRules = [
                  {
                    groups = [ "wheel" ];
                    commands = [
                      {
                        command = "ALL";
                        options = [ "NOPASSWD" ];
                      }
                    ];
                  }
                ];

              }
            ]
            true # secure boot
            false # impermanence.nix
        ;

        l-x13s =
          mkNixOS "aarch64-linux" "l-x13s"
            [
              nixos-x13s.nixosModules.default
              ./hardware/l-x13s/hardware-configuration.nix
            ]
            [
              home-manager.nixosModules.home-manager
              ./home-manager/l-x13s/home.nix
              ./time/timezone.nix
              {
                networking.hostName = "l-x13s";
                networking.networkmanager.enable = true;
                nixpkgs.config.allowUnfree = true;
                boot.loader.systemd-boot.configurationLimit = 15;
                nixpkgs.overlays = [ nixos-aarch64-widevine.overlays.default ];
              }
              ./packages/l-x13s/widevine.nix
              ./desktop/fonts.nix
              ./desktop/environment.nix
              ./system/garbage-collection.nix
              ./system/locale.nix
              ./network/firewall.nix
              ./desktop/applets.nix
              ./desktop/darkmode.nix
              ./desktop/shell-env.nix
              ./desktop/users-and-groups.nix
              ./system/version.nix
              ./system/autoupdate.nix
              ./packages/l-x13s/packages.nix
              ./general/tooling.nix
              {
                environment.interactiveShellInit = ''
                  ZSH_THEME=trapd00r
                '';
              }
            ]
            true # secure boot
            false # impermanence
        ;

      };

      packages.x86_64-linux = {
        # default = self.nixosConfigurations.default.config.system.build.toplevel;
      };
    };
}
