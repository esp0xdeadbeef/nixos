{ config, pkgs, ... }:
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
  services.displayManager.defaultSession = "xfce+i3";
  services.xserver.displayManager.gdm.enable = true;
  # services.displayManager.autoLogin.user = "deadbeef";
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