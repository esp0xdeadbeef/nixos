{ pkgs, ... }:
{
  imports = [
    ./impermanence.nix
    ./lanzaboote.nix
    ./clevis.nix
  ];
}
