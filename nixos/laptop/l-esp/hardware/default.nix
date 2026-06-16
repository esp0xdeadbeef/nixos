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
    ./suspend-to-disk.nix
    ./tmpfs.nix
  ];

  boot.kernelModules = [ "iwlwifi" ];
}
