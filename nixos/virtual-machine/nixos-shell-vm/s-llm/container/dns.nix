{ lib, ... }:
{
  #services.resolved.enable = false;
  services.resolved.enable = true;

  networking.nameservers = [ ];
  networking.useHostResolvConf = lib.mkForce false;
}
