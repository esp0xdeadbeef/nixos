{ lib, ulaPrefix, tenantV4Base }:

topo:

let
  addr = import ./addressing.nix { inherit lib; };

  isTransport =
    l:
      lib.elem (l.kind or null) [ "lan" "p2p" "wan" ];
in
{
  inherit (topo) domain nodes;

  links =
    lib.mapAttrs
      (_: l:
        if !isTransport l then
          # Non-transport / logical-only links pass through untouched
          l
        else
          let
            members = l.members or [ ];
            kind = l.kind;
          in
          {
            inherit (l)
              kind
              carrier
              name
              vlanId
              members
              ;

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
                        # ─────────────────────────────
                        # P2P auto-addressing (ONLY if NOT explicitly set)
                        # ─────────────────────────────
                        // (lib.optionalAttrs
                              (kind == "p2p" && !(ep ? addr4))
                              {
                                addr4 = addr.mkP2P4 {
                                  v4Base = tenantV4Base;
                                  vlanId = l.vlanId;
                                  node = n;
                                  members = members;
                                };
                              }
                           )
                        // (lib.optionalAttrs
                              (kind == "p2p" && !(ep ? addr6))
                              {
                                addr6 = addr.mkP2P6 {
                                  ulaPrefix = ulaPrefix;
                                  vlanId = l.vlanId;
                                  node = n;
                                  members = members;
                                };
                              }
                           )

                        # ─────────────────────────────
                        # Tenant LAN gateway addressing (ONLY if NOT explicitly set)
                        # ─────────────────────────────
                        // (lib.optionalAttrs
                              (kind == "lan" && isGw && !(ep ? addr4))
                              {
                                addr4 = addr.mkTenantV4 {
                                  v4Base = tenantV4Base;
                                  vlanId = l.vlanId;
                                };
                              }
                           )
                        // (lib.optionalAttrs
                              (kind == "lan" && isGw && !(ep ? addr6))
                              {
                                addr6 = addr.mkTenantV6 {
                                  ulaPrefix = ulaPrefix;
                                  vlanId = l.vlanId;
                                };
                              }
                           );
                    }
                  )
                  members
              );
          }
      )
      topo.links;
}

