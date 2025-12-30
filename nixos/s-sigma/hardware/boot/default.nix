{ pkgs, ... }:
{
  imports = [
    ./bootloader.nix
    ./boot-package.nix
  ];
}
