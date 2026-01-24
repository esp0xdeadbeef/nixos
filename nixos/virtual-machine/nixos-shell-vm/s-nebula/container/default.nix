{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./networking.nix
    ./container-settings.nix
    #./unifi.nix
    ./nebula.nix
  ];
  system.stateVersion = "25.11";
}
