# Opt-in profile: remove the network defaults the NixOS container machinery
# injects, so the network renderers own the full network realization and can
# set plain values without fighting `mkDefault`/`mkForce` priorities.
#
# Applied explicitly by the router hosts (s-router-cobalt / s-router-neon) so
# the override is visible and opt-in, and the stock container defaults stay
# available for everything else.
#
# Removed:
#   - nixos-containers.nix: `networking.useDHCP = false` (redundant with the
#     NixOS default, and a network opinion the container should not hold).
#   - networkd.nix: `services.resolved.enable = mkDefault true` (assumes
#     "networkd implies resolved", which is wrong for a router container).
{ lib, pkgs, ... }:

let
  patched = name: modulePath: find:
    builtins.toFile name (
      builtins.replaceStrings [ find ] [ "" ] (builtins.readFile modulePath)
    );
in
{
  disabledModules = [
    "virtualisation/nixos-containers.nix"
    "system/boot/networkd.nix"
  ];

  imports = [
    (patched
      "nixos-containers-no-network.nix"
      "${pkgs.path}/nixos/modules/virtualisation/nixos-containers.nix"
      "networking.useDHCP = false;")
    (patched
      "networkd-no-resolved.nix"
      "${pkgs.path}/nixos/modules/system/boot/networkd.nix"
      "services.resolved.enable = mkDefault true;")
  ];
}
