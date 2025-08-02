{ config, pkgs, lib, ... }:
{
  services.openssh.enable = true;
  users.users = {
    deadbeef = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKIjWf+YcfijNBH+ilujFPNpgVZH9jD1PA1GiIzIWxO deadbeef@l-x13s"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgBgeVe/DSMZQAY8iS1D5Db3IbyteDSW+l79ZFD8Rmg"
      ];
    };
  };
  programs.sway.enable = true;
  services.displayManager.defaultSession =  "sway";
  services.xserver.displayManager.gdm.enable = true;
  # services.displayManager.sddm.enable = true;
  programs.xwayland.enable = true;
  services.displayManager.autoLogin.user = "deadbeef";
  services.getty.autologinUser = "deadbeef";
  services.getty.autologinOnce = true;

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
