# ./container/network/default.nix
{ pkgs, ... }:
{
  imports = [
    ./wan.nix
    ./network.nix

    ./downstream-s-router-legacy-edge.nix
    ./downstream-s-router-edge.nix
    ./ipv6-handover.nix
    ./legacy-assertions.nix
  ];
}
