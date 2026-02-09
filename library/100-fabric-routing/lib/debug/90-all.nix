# lib/debug/90-all.nix
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;

  routed = import ./30-routing.nix;

in
{
  topology = {
    domain = routed.domain;
    nodes = builtins.attrNames routed.nodes;
    links = builtins.attrNames routed.links;
  };

  nodes = builtins.mapAttrs (
    n: _:
    import ./view-node.nix {
      inherit lib pkgs;
      ulaPrefix = "fd42:dead:beef";
      tenantV4Base = "10.10";
    } n routed
  ) routed.nodes;

  wan = import ./50-wan.nix;

  multiWan = import ./60-multi-wan.nix;
}
