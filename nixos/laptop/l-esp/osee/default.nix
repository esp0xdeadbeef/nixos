{ pkgs, ... }:
{
  imports = [
    ./lxc-osee/bind-to-lxc.nix
    ./lxc-osee/x2go-client.nix
    ./rev-tooling/ghidra.nix
  ];
}
