{ pkgs, ... }:
{
  imports = [
    ./debug-packages.nix
    ./disk-layout.nix
    ./minecraft-services.nix
    ../1-default-vm-settings
  ];
}
