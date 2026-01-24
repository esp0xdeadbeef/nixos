{ config, pkgs, ... }:
{
  services.displayManager.autoLogin.user = "deadbeef";
  services.getty.autologinUser = "deadbeef";
  services.getty.autologinOnce = true;
}
