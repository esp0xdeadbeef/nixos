# lib/debug/route-matrix.nix
{ lib, pkgs }:

topo:

let
  nodes = lib.attrNames topo.nodes;

  viewFor =
    node:
      import ./view-node.nix {
        inherit lib pkgs;
      } node topo;

in
lib.listToAttrs (
  map (n: {
    name = n;
    value = viewFor n;
  }) nodes
)

