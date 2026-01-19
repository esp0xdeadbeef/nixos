{ pkgs, ... }:
{
  imports = [
    ./vm-settings.nix
    ./start-container.nix
    ./network.nix
  ];
}
