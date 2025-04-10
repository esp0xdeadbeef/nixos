{ mkNixOS }:

{
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
}