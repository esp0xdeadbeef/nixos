{ pkgs, ... }:
{
  # Enable GNOME
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Bypass the login screen automatically for your user
  services.displayManager.autoLogin = {
    enable = true;
    user = "deadbeef";
  };

  # Workaround for GNOME autologin issue where the screen locks anyway
  services.xserver.displayManager.gdm.autoLogin.delay = 0;
}

