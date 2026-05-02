{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./networking.nix
    ./dns.nix
  ];
  system.stateVersion = "25.11";
}
