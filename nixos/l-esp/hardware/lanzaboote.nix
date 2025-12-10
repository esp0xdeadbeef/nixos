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
    autoGenerateKeys.enable = true;

    pkiBundle = "/persist/var/lib/sbctl";

  #pkiBundle = {
  #  externalPath = "/persist/var/lib/sbctl";
  #};
  };
}
