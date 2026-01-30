{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./networking.nix
    #./unifi.nix
    ./nebula.nix
    ./dns.nix
  ];
  system.stateVersion = "25.11";
}
