{ pkgs, ... }:
{
  imports = [
    ./boot-package.nix
    ./bootloader.nix
    ./force-update.nix
    ./impermanence.nix
    ./lanzaboote.nix
    ./swap-and-tmpfs.nix
    ./network-onlymgmt.nix
    ./network-hypervisor-isp.nix
    ./hardware-configuration.nix
    ./network-hypervisor-lan.nix
    ./network-general.nix
  ];
}
