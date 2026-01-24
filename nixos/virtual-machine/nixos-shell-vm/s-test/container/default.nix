{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./networking.nix
    ./container-settings.nix
    ./podman-hello-world.nix
    ./debug-packages.nix
    ./podman-fix.nix
  ];
  system.stateVersion = "25.11";
}
