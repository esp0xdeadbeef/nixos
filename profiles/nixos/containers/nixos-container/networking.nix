{ lib, ... }:

{
  #networking.useNetworkd = lib.mkDefault true;

  networking.networkmanager.enable = lib.mkDefault true;
  # mkForce if you need to overwrite, this is already defined in /nixos/modules/virtualisation/container-config.nix
  networking.useHostResolvConf = false;

}
