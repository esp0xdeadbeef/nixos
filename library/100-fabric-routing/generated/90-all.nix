{ lib }:
let
  routed = import ./30-routing.nix { inherit lib; };
in
{
  topology = {
    domain = routed.domain;
    nodes = builtins.attrNames routed.nodes;
    links = builtins.attrNames routed.links;
  };

  nodes = builtins.mapAttrs (n: _: routed.nodes.${n}) routed.nodes;
}
