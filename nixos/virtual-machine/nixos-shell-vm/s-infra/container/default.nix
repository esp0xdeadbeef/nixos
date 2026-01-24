{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./debug-packages.nix
    ./podman-game-services.nix
    ./networking.nix
    ./container-settings.nix
  ];
  system.stateVersion = "25.11";
}
