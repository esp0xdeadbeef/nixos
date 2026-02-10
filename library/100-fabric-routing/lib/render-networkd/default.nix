{ lib }:

let
  utils = import ./utils.nix { inherit lib; };
  names = import ./names.nix { inherit lib; };
  routes = import ./routes.nix { inherit lib; };
  parentIf = import ./parent-if.nix { inherit lib; } { inherit utils; };

  mkUnits = import ./interface-units.nix { inherit lib; } { inherit names routes parentIf; };

in
{
  render =
    {
      all,
      nodeName,
      topologyRaw ? null,
    }:
    let
      all' =
        all
        // lib.optionalAttrs (topologyRaw != null) {
          topologyRaw = topologyRaw;
        };

      ifaces = all'.nodes.${nodeName}.interfaces or { };

      units = lib.mapAttrsToList (
        linkName: iface:
        mkUnits {
          all = all'; # ← THIS WAS THE BUG
          inherit nodeName linkName iface;
        }
      ) ifaces;

    in
    {
      netdevs = lib.foldl' (a: b: a // b.netdevs) { } units;
      networks = lib.foldl' (a: b: a // b.networks) { } units;
    };
}
