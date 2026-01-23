{
  lib,
  pkgs,
  config,
  ...
}:
{
  imports = [
    ./networking.nix
    ./container-settings.nix
./podman-hello-world.nix
    ../../1-helpers/debug-packages.nix
    ../../1-helpers/podman-fix.nix
  ];
  system.stateVersion = "25.11";
}
