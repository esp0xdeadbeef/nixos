{ config, pkgs, ... }:

{
  imports = [
     ./nixos-vm-configuration/network.nix
     ./nixos-vm-configuration/debug-packages.nix
  ];
  system.stateVersion = "25.11";

  services.openssh.enable = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.device = "nodev";
  boot.loader.efi.canTouchEfiVariables = false;

  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];
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
  services.displayManager.autoLogin.user = "deadbeef";
  services.getty.autologinUser = "deadbeef";
  services.getty.autologinOnce = true;
  users.users = {
    deadbeef = {
      initialPassword = " ";
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };
  };

  systemd.services."serial-getty@ttyS0".enable = true;
}

