{ lib, outPath ? null }:

let
  fabricPath =
    if outPath == null then
      null
    else
      "${outPath}/library/100-fabric-routing/inputs/intent.nix";

  fabricImported =
    if fabricPath != null && builtins.pathExists fabricPath then
      import fabricPath
    else
      { };

  fabricInputs =
    if builtins.isFunction fabricImported then
      fabricImported { inherit lib; }
    else
      fabricImported;

  policyBase =
    if fabricInputs ? policyAccessTransitBase then
      fabricInputs.policyAccessTransitBase
    else
      100;

  corePolicyTransitVlan =
    if fabricInputs ? corePolicyTransitVlan then
      fabricInputs.corePolicyTransitVlan
    else
      null;

  mkTransitBridge = name: vlan: {
    inherit name vlan;
    parentUplink = "trunk";
  };

  upstreamTransitVlan =
    if corePolicyTransitVlan != null then
      corePolicyTransitVlan
    else
      policyBase + 3;

  transitBridges =
    {
      tr100 = mkTransitBridge "tr100" policyBase;
      tr101 = mkTransitBridge "tr101" (policyBase + 1);
      tr102 = mkTransitBridge "tr102" (policyBase + 2);
      "tr${toString upstreamTransitVlan}" =
        mkTransitBridge "tr${toString upstreamTransitVlan}" upstreamTransitVlan;
    };
in
{
  schemaVersion = 1;

  deployment.hosts.s-router-policy-only = {
    uplinks = {
      management = {
        parent = "eth0";
        bridge = "vlan2";
        mode = "vlan";
        vlan = 2;
      };

      trunk = {
        parent = "eth0";
        bridge = "br-lan-trunk";
        mode = "trunk";
      };
    };

    bridgeNetworks = {
      vlan2 = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
        ConfigureWithoutCarrier = true;
      };

      br-lan-trunk = {
        ConfigureWithoutCarrier = true;
      };
    };

    transitBridges = transitBridges;
  };

  realization.nodes.s-router-policy = {
    host = "s-router-policy-only";
    platform = "nixos-container";

    ports = {
      lan = {
        link = "p2p-s-router-policy-s-router-upstream-selector";
        attach = {
          kind = "bridge";
          bridge = "tr${toString upstreamTransitVlan}";
        };
        interface.name = "lan";
      };

      transit-admin = {
        link = "p2p-s-router-access-admin-s-router-policy";
        attach = {
          kind = "bridge";
          bridge = "tr100";
        };
        interface.name = "transit-admin";
      };

      transit-mgmt = {
        link = "p2p-s-router-access-mgmt-s-router-policy";
        attach = {
          kind = "bridge";
          bridge = "tr101";
        };
        interface.name = "transit-mgmt";
      };

      transit-client = {
        link = "p2p-s-router-access-client-s-router-policy";
        attach = {
          kind = "bridge";
          bridge = "tr102";
        };
        interface.name = "transit-client";
      };
    };
  };
}
