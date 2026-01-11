{ pkgs, ... }:
{
  imports = [
    ./debug-packages.nix
    ./unifi.nix
    ./vm-settings.nix
    ./network.nix
  ];
}
