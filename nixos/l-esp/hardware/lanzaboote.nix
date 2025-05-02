{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
{
  # Force disable systemd-boot as Lanzaboote replaces it
  boot.loader.systemd-boot.enable = lib.mkForce false;
  
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/persist/etc/secureboot";
  };
}