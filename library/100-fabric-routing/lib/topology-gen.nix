{ lib }:
{
  domain ? "lan.",

  tenantVlans ? [
    10
    20
    30
    40
    50
    60
    70
    80
  ],

  policyAccessTransitBase ? 100,
  corePolicyTransitVlan ? 200,

  defaultTenantUpstream ? "core",
  tenantUpstreamMap ? { },
}:

let
  vids = lib.sort lib.lessThan tenantVlans;

  accessNode = vid: "s-router-access-${toString vid}";
  policyNode = "s-router-policy-only";
  coreNode = "s-router-core-wan";

  tenantUpstreamFor = vid: tenantUpstreamMap.${toString vid} or defaultTenantUpstream;

  transitVidForAccess =
    vid:
    let
      tvid = policyAccessTransitBase + vid;
    in
    if tvid < 0 || tvid > 255 then
      throw ''
        topology-gen: computed transit VLAN ${toString tvid}
        for tenant VLAN ${toString vid} is out of range (0..255)

        This VLAN cannot be used for p2p ffXX IPv6 encoding.
      ''
    else
      tvid;

  p2pVids = vids;

in
{
  inherit domain;

  nodes = lib.listToAttrs (
    [
      {
        name = coreNode;
        value = {
          ifs = {
            lan = "lan";
            wan = "wan";
          };
        };
      }
      {
        name = policyNode;
        value = {
          ifs = {
            lan = "lan";
          };
        };
      }
    ]
    ++ map (vid: {
      name = accessNode vid;
      value = {
        ifs = {
          lan = "lan";
        };
      };
    }) vids
  );

  links = lib.listToAttrs (

    [
      {
        name = "policy-core";
        value = {
          kind = "p2p";
          carrier = "lan";
          vlanId = corePolicyTransitVlan;
          name = "policy-core";
          members = [
            policyNode
            coreNode
          ];
        };
      }
    ]

    ++ map (
      vid:
      let
        tvid = transitVidForAccess vid;
      in
      {
        name = "policy-access-${toString vid}";
        value = {
          kind = "p2p";
          carrier = "lan";
          vlanId = tvid;
          name = "policy-access-${toString vid}";
          members = [
            policyNode
            (accessNode vid)
          ];
          endpoints = {
            "${accessNode vid}" = {
              tenant = {
                vlanId = vid;
              };
              export = true;
              upstream = tenantUpstreamFor vid;
            };
          };
        };
      }
    ) p2pVids

    ++ map (vid: {
      name = "access-tenant-${toString vid}";
      value = {
        kind = "lan";
        carrier = "lan";
        vlanId = vid;
        name = "access-tenant-${toString vid}";
        members = [ (accessNode vid) ];
        endpoints = {
          "${accessNode vid}" = {
            tenant = {
              vlanId = vid;
            };
            gateway = true;
          };
        };
      };
    }) vids
  );
}
