# lib/topology-resolve.nix
#
# Mechanical topology resolver.
# Turns intent into fully-resolved endpoints.
# NO policy. NO debug logic. NO rendering assumptions.

{ lib }:

topo:

let
  site = import ./site-addressing.nix {};
  addr = import ./addressing.nix { inherit lib site; };

in
{
  inherit (topo) domain nodes;

  links =
    lib.mapAttrs
      (_: l:
        let
          members = l.members or [];
          kind = l.kind;
        in
        {
          inherit (l) kind carrier name vlanId members;

          endpoints =
            lib.listToAttrs (
              map
                (n:
                  let
                    ep = (l.endpoints or {}).${n} or {};
                  in
                  {
                    name = n;
                    value =
                      ep
                      // {
                        addr4 =
                          ep.addr4 or (
                            if kind == "p2p"
                            then addr.mkP2P4 {
                              vlanId = l.vlanId;
                              node = n;
                              members = members;
                            }
                            else null
                          );

                        addr6 =
                          ep.addr6 or (
                            if kind == "p2p"
                            then addr.mkP2P6 {
                              vlanId = l.vlanId;
                              node = n;
                              members = members;
                            }
                            else null
                          );
                      };
                  }
                )
                members
            );
        }
      )
      topo.links;
}

