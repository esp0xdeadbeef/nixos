{ pkgs, ... }:
{
  imports = [
    ././boot
    ././disks
    ././network
    ././qol
    ./hardware-configuration.nix
  ];
}
