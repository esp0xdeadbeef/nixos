{ mkNixOS }:

{
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
}
