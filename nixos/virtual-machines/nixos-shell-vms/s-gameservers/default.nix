{ pkgs, ... }:
{
  imports = [
    ./debug-packages.nix
    ./disk-layout.nix
    ./vm-settings.nix
    ./minecraft-services.nix
  ];
}
