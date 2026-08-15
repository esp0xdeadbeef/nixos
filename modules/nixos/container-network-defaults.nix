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
{ inputs, lib, ... }:

let
  nixpkgsSrc = inputs.nixpkgs;

  # networkd.nix with the implicit `resolved = mkDefault true` stripped. This
  # module is injected into each container's eval-config via the patched
  # nixos-containers module below, because the container evaluates its own
  # copy of the nixpkgs base modules and a host-level disabledModules does not
  # reach inside it.
  networkdNoResolved = builtins.toFile "networkd-no-resolved.nix" (
    builtins.replaceStrings
      [ "services.resolved.enable = mkDefault true;" ]
      [ "" ]
      (builtins.readFile "${nixpkgsSrc}/nixos/modules/system/boot/networkd.nix")
  );

  # nixos-containers.nix with the redundant useDHCP removed and the patched
  # networkd injected into every container's eval-config.
  nixosContainersNoNetwork = builtins.toFile "nixos-containers-no-network.nix" (
    builtins.replaceStrings
      [
        "networking.useDHCP = false;"
        "                            { options, ... }:\n                            {\n                              config = {"
      ]
      [
        ""
        "                            { options, ... }:\n                            {\n                              disabledModules = [ \"system/boot/networkd.nix\" ];\n                              imports = [ ${networkdNoResolved} ];\n                              config = {"
      ]
      (builtins.readFile "${nixpkgsSrc}/nixos/modules/virtualisation/nixos-containers.nix")
  );
in
{
  disabledModules = [
    "virtualisation/nixos-containers.nix"
  ];

  imports = [
    nixosContainersNoNetwork
  ];
}
