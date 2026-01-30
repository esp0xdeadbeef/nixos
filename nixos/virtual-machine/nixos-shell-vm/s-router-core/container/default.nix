{ pkgs, ... }:
{
  imports = [
    ./network
    ./services
    ./qol
    ./hardware
    ./generic-settings.nix
  ];
}
