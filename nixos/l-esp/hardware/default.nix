{ pkgs, ... }:
{
  imports = [
    ./audio.nix
    ./bluetooth.nix
    ./bootloader.nix
    ./hardware-configuration.nix
    ./impermanence.nix
    ./lanzaboote.nix
    ./nvidia.nix
    ./steam.nix
    ./swap-and-tmpfs.nix
  ];
}
