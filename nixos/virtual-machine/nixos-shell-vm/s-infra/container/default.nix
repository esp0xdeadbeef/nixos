{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./networking.nix
    ./container-settings.nix
    ./unifi.nix
    ./ipref3.nix
  ];
  system.stateVersion = "25.11";
}
