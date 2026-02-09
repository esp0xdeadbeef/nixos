# lib/debug/95-routing-table.nix
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;

  routed = import ./30-routing.nix;

  mk =
    node:
    let
      links = lib.filterAttrs (_: l: lib.elem node (l.members or [ ])) routed.links;

      eps = lib.concatMap (
        l:
        let
          ep = (l.endpoints or { }).${node} or { };
        in
        (ep.routes4 or [ ]) ++ (ep.routes6 or [ ])
      ) (lib.attrValues links);
    in
    eps;

in
lib.listToAttrs (
  map (n: {
    name = n;
    value = mk n;
  }) (lib.attrNames routed.nodes)
)
