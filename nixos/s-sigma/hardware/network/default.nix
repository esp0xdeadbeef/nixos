{ pkgs, ... }:
{
  imports = [
    ./setup-mgmt.nix
    ./qemu-and-fw.nix
    ./setup-bridge-adapters.nix
  ];
}
