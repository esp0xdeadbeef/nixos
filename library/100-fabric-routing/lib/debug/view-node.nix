# lib/debug/view-node.nix
{ lib, pkgs }:

nodeName: topo:

let
  fabrics = import ../fabrics.nix { inherit lib; };
  site = import ../site-addressing.nix {};
  addr = import ../addressing.nix { inherit lib site; };

  linksAll = topo.links or {};

  links =
    lib.filterAttrs (_: l: lib.elem nodeName (l.members or [])) linksAll;

  endpoints =
    lib.mapAttrs
      (_: l:
        let ep = (l.endpoints or {}).${nodeName} or {};
        in {
          kind = l.kind;
          vlanId = l.vlanId;
          fabric = fabrics.fabricKeyForVlan l.vlanId;
          addr4 =
            ep.addr4 or (
              if l.kind == "p2p"
              then addr.mkP2P4 { vlanId = l.vlanId; node = nodeName; members = l.members; }
              else null
            );
          addr6 =
            ep.addr6 or (
              if l.kind == "p2p"
              then addr.mkP2P6 { vlanId = l.vlanId; node = nodeName; members = l.members; }
              else null
            );
          routes4 = ep.routes4 or [];
          routes6 = ep.routes6 or [];
          export = ep.export or false;
        }
      )
      links;

in
{
  node = nodeName;
  interfaces = endpoints;
}

