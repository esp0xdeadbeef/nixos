# lib/topology-gen.nix
{ lib }:

{
  domain ? "lan.",
  tenantVlans ? [ 10 20 30 40 50 60 70 80 ],

  coreIfs ? { lan = "lan"; wan = "wan"; },
  policyIfs ? { lan = "lan"; },
  accessIfs ? { lan = "lan"; },

  # Transit VLAN ranges / placement
  # policy<->access: 100 + tenantVlan (so tenant 60 -> transit 160)
  policyAccessTransitBase ? 100,

  # policy<->core transit VLAN
  corePolicyTransitVlan ? 200,
}:

let
  vids = lib.sort lib.lessThan tenantVlans;

  accessNode = vid: "s-router-access-${toString vid}";

  # transit VLAN is base + tenant VLAN id (tenant 60 -> transit 160)
  transitVidForAccess =
    vid:
      let tvid = policyAccessTransitBase + vid;
      in
      if vid < 0 || vid > 4094 then
        throw "topology-gen: invalid tenant VLAN ${toString vid}"
      else if tvid < 0 || tvid > 255 then
        throw ''
          topology-gen: computed transit VLAN ${toString tvid} for tenant VLAN ${toString vid} is out of range 0..255.
          Your IPv6 ffXX encoding requires transit VLANs <= 255.
          Fix by lowering tenant VLANs, lowering base, or changing the IPv6 encoding scheme.
        ''
      else
        tvid;

in
{
  inherit domain;

  nodes =
    lib.listToAttrs (
      [
        { name = "s-router-core-wan"; value = { ifs = coreIfs; }; }
        { name = "s-router-policy-only"; value = { ifs = policyIfs; }; }
      ]
      ++ map (vid: { name = accessNode vid; value = { ifs = accessIfs; }; }) vids
    );

links =
  lib.listToAttrs (
    # core <-> policy
    [
      {
        name = "policy-core";
        value = {
          kind = "p2p";
          carrier = "lan";
          vlanId = corePolicyTransitVlan;
          name = "policy-core";
          members = [
            "s-router-policy-only"
            "s-router-core-wan"
          ];
        };
      }
    ]

    # policy <-> access transit
    ++ map
      (vid:
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
              "s-router-policy-only"
              (accessNode vid)
            ];
            endpoints = {
              "${accessNode vid}" = {
                tenant = { vlanId = vid; };
                export = true;
              };
            };
          };
        }
      )
      vids

    # access tenant LANs (gateway ownership)
    ++ map
      (vid:
        {
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
        }
      )
      vids
  );

}

