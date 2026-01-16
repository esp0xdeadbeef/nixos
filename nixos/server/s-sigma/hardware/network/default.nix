{ pkgs, ... }:
{
  imports = [
    ./setup-mgmt.nix
    ./qemu-and-fw.nix
    ./setup-bridge-lan.nix
    ./setup-bridge-isp.nix
  ];
}
