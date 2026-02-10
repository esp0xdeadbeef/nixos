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

  # default upstream selector
  defaultTenantUpstream ? "core",

  # optional per-tenant override
  tenantUpstreamMap ? { },
}:

let
  vids = lib.sort lib.lessThan tenantVlans;

  accessNode = vid: "s-router-access-${toString vid}";
  policyNode = "s-router-policy-only";
  coreNode   = "s-router-core-wan";

  tenantUpstreamFor =
    vid:
      tenantUpstreamMap.${toString vid} or defaultTenantUpstream;

  #
  # Transit VLAN calculator (hard invariant: <=255)
  #
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

  #
  # LEGACY ESCAPE HATCH
  # VLAN 1010 must exist as LAN but must NEVER become a p2p transit
  #
  p2pVids = lib.filter (vid: vid != 1010) vids;

in
{
  inherit domain;

  nodes =
    lib.listToAttrs (
      [
        {
          name = coreNode;
          value = { ifs = { lan = "lan"; wan = "wan"; }; };
        }
        {
          name = policyNode;
          value = { ifs = { lan = "lan"; }; };
        }
      ]
      ++ map (vid: {
        name = accessNode vid;
        value = { ifs = { lan = "lan"; }; };
      }) vids
    );

  links =
    lib.listToAttrs (

      #
      # core ↔ policy (fixed transit)
      #
      [
        {
          name = "policy-core";
          value = {
            kind = "p2p";
            carrier = "lan";
            vlanId = corePolicyTransitVlan;
            name = "policy-core";
            members = [ policyNode coreNode ];
          };
        }
      ]

      #
      # legacy / transitional upstream (VLAN 1010)
      #
      ++ [
        {
          name = "policy-upstream-1010";
          value = {
            kind = "wan";
            carrier = "lan";
            vlanId = 1010;
            name = "policy-upstream-1010";
            members = [ policyNode coreNode ];

            endpoints = {
              "${policyNode}" = {
                addr4 = "10.255.255.2/29";
                addr6 = "fd42:dead:beef:1010::2/64";

                routes4 = [
                  { dst = "0.0.0.0/0"; via4 = "10.255.255.1"; }
                ];

                routes6 = [
                  { dst = "::/0"; via6 = "fd42:dead:beef:1010::3"; }
                ];
              };
            };
          };
        }
      ]

      #
      # policy ↔ access (ONLY non-legacy VLANs)
      #
      ++ map
        (vid:
          let tvid = transitVidForAccess vid;
          in {
            name = "policy-access-${toString vid}";
            value = {
              kind = "p2p";
              carrier = "lan";
              vlanId = tvid;
              name = "policy-access-${toString vid}";
              members = [ policyNode (accessNode vid) ];
              endpoints = {
                "${accessNode vid}" = {
                  tenant = { vlanId = vid; };
                  export = true;
                  upstream = tenantUpstreamFor vid;
                };
              };
            };
          }
        )
        p2pVids

      #
      # access ↔ tenant LANs (ALL VLANs, INCLUDING 1010)
      #
      ++ map
        (vid: {
          name = "access-tenant-${toString vid}";
          value = {
            kind = "lan";
            carrier = "lan";
            vlanId = vid;
            name = "access-tenant-${toString vid}";
            members = [ (accessNode vid) ];
            endpoints = {
              "${accessNode vid}" = {
                tenant = { vlanId = vid; };
                gateway = true;
              };
            };
          };
        })
        vids
    );
}

