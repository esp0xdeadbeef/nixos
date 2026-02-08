# lib/debug/debug-eval.nix
#
# Canonical debug entrypoint.
# Shows exactly what the renderers will see.
# No topology interpretation here.

let
  pkgs = import <nixpkgs> {};
  lib  = pkgs.lib;

  topo = import ../topology.nix { };

  viewNode =
    node:
      import ./view-node.nix {
        inherit lib pkgs;
      } node topo;

  nodes = lib.attrNames (topo.nodes or {});

in
{
  topology = {
    domain = topo.domain;
    nodes  = nodes;
    links  = lib.attrNames (topo.links or {});
  };

  nodes =
    lib.listToAttrs (
      map (n: {
        name = n;
        value = viewNode n;
      }) nodes
    );
}

