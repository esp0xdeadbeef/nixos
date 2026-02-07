# ./container/default.nix
{ outPath, pkgs, ... }:
{
  imports = [
    "${outPath}/library/1010-router-legacy-edge"

    ./make-vlan-bridges.nix

    ./network
    ./services
    ./qol
    ./hardware
    ./generic-settings.nix
  ];
}

