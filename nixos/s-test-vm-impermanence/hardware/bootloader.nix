{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";
  # boot.lanzaboote = {
  #   enable = true;
  #   pkiBundle = "/persistent/initrd/secureboot";
  #   # generateKeysIfNotExist = true;
  # };

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/boot".neededForBoot = true;

  environment.systemPackages = with pkgs; [ sbctl ];
}
