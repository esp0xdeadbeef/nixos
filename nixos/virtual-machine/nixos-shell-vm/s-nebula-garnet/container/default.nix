{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./networking.nix
    ./nebula.nix
    ./dns.nix
  ];
  system.stateVersion = "26.05";
}
