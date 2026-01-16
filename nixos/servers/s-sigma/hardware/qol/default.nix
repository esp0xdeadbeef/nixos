{ pkgs, ... }:
{
  imports = [
    ./force-update.nix
    ./swap-and-tmpfs.nix
  ];
}
