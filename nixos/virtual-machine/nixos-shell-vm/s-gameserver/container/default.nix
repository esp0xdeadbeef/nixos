{
  lib,
  pkgs,
  config,
  ...
}:
{
  imports = [
    ./debug-packages.nix
    ./podman-game-services.nix
    ./podman-mc-prod.nix
    ./podman-mc-test.nix
    ./podman-valheim.nix
    ./networking.nix
    ./container-settings.nix
    ./firewall.nix
  ];
  system.stateVersion = "25.11";
}
