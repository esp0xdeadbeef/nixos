{ pkgs, lib, ... }:
{
  imports = [
    ./debug-packages.nix
    ./networking.nix
    ./networking-systemd.nix
    ./podman-kernel-params.nix
  ];
  system.stateVersion = lib.mkDefault "25.11";
}
