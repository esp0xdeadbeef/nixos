{ mkNixOS }:

{
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
}
