{ pkgs, ... }:
{
  imports = [
    ./wan.nix
    ./network.nix
    ./downstream-s-router-legacy-edge.nix
  ];
}
