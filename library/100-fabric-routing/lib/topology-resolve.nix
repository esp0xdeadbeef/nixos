# lib/topology-resolve.nix
{ lib, ulaPrefix, tenantV4Base }:

topo:

let
  addr = import ./addressing.nix { inherit lib; };

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
                    isGw = ep.gateway or false;
                  in
                  {
                    name = n;
                    value =
                      ep
                      // (lib.optionalAttrs (kind == "p2p") {
                        addr4 = addr.mkP2P4 {
                          v4Base = tenantV4Base;
                          vlanId = l.vlanId;
                          node = n;
                          members = members;
                        };
                        addr6 = addr.mkP2P6 {
                          ulaPrefix = ulaPrefix;
                          vlanId = l.vlanId;
                          node = n;
                          members = members;
                        };
                      })
                      // (lib.optionalAttrs (kind == "lan" && isGw) {
                        addr4 = addr.mkTenantV4 {
                          v4Base = tenantV4Base;
                          vlanId = l.vlanId;
                        };
                        addr6 = addr.mkTenantV6 {
                          ulaPrefix = ulaPrefix;
                          vlanId = l.vlanId;
                        };
                      });
                  }
                )
                members
            );
        }
      )
      topo.links;
}


