{ pkgs, ... }:
{
  imports = [
    ./debug-packages.nix
    ./disk-layout.nix
    ./minecraft-services.nix
    ../default-vm-settings
  ];
}
