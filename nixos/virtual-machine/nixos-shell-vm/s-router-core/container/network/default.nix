{ pkgs, ... }:
{
  imports = [
    ./wan.nix
    ./network.nix
    ./downstream-s-router-edge.nix
  ];
}
