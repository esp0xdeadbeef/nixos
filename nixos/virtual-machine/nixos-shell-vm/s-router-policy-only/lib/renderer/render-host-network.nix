{
  lib,
  inventory,
  hostName,
  cpm ? null,
}:

let
  validated = import ../inventory/validate.nix {
    inherit
      lib
      inventory
      hostName
      cpm
      ;
  };

  transitBridgeHelpers = import ../fabric/transit-bridges.nix { inherit lib; };

  host = validated.deployment.hosts.${hostName};

  uplinks = host.uplinks;
  uplinkNames = builtins.attrNames uplinks;

  bridgeNetworkFor =
    bridge:
    if host ? bridgeNetworks && builtins.hasAttr bridge host.bridgeNetworks then
      host.bridgeNetworks.${bridge}
    else
      { ConfigureWithoutCarrier = true; };

  transitBridges = transitBridgeHelpers.load host;
  transitNames = transitBridgeHelpers.names transitBridges;
  transitNamesForUplink = transitBridgeHelpers.namesForUplink transitBridges;

  uplinkNetdevs = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        transitNamesOnUplink = transitNamesForUplink uplinkName;
        vlanIfName = "${uplink.parent}.${toString uplink.vlan}";
      in
      [
        {
          name = "10-${uplink.bridge}";
          value.netdevConfig = {
            Name = uplink.bridge;
            Kind = "bridge";
          };
        }
      ]
      ++ lib.optionals (uplink.mode == "vlan") [
        {
          name = "11-${vlanIfName}";
          value = {
            netdevConfig = {
              Name = vlanIfName;
              Kind = "vlan";
            };
            vlanConfig.Id = uplink.vlan;
          };
        }
      ]
      ++ lib.optionals (uplink.mode == "trunk") (
        map (
          transitName:
          let
            transit = transitBridges.${transitName};
            transitVlanIfName = "${uplink.bridge}.${toString transit.vlan}";
          in
          {
            name = "12-${transitVlanIfName}";
            value = {
              netdevConfig = {
                Name = transitVlanIfName;
                Kind = "vlan";
              };
              vlanConfig.Id = transit.vlan;
            };
          }
        ) transitNamesOnUplink
      )
    ) uplinkNames
  );

  uplinkParentNetworks = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        vlanIfName = "${uplink.parent}.${toString uplink.vlan}";
      in
      if uplink.mode == "vlan" then
        [
          {
            name = "05-${uplink.parent}";
            value = {
              matchConfig.Name = uplink.parent;
              networkConfig = {
                VLAN = [ vlanIfName ];
                DHCP = "no";
                IPv6AcceptRA = false;
                ConfigureWithoutCarrier = true;
              };
            };
          }
          {
            name = "05-${vlanIfName}";
            value = {
              matchConfig.Name = vlanIfName;
              networkConfig = {
                Bridge = uplink.bridge;
                DHCP = "no";
                IPv6AcceptRA = false;
                ConfigureWithoutCarrier = true;
              };
            };
          }
        ]
      else
        [
          {
            name = "05-${uplink.parent}";
            value = {
              matchConfig.Name = uplink.parent;
              networkConfig = {
                Bridge = uplink.bridge;
                DHCP = "no";
                IPv6AcceptRA = false;
                ConfigureWithoutCarrier = true;
              };
            };
          }
        ]
    ) uplinkNames
  );

  uplinkBridgeNetworks = builtins.listToAttrs (
    map (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        bridgeNetwork = bridgeNetworkFor uplink.bridge;
        transitNamesOnUplink = transitNamesForUplink uplinkName;
      in
      {
        name = "06-${uplink.bridge}";
        value = {
          matchConfig.Name = uplink.bridge;
          networkConfig =
            bridgeNetwork
            // lib.optionalAttrs (uplink.mode == "trunk" && transitNamesOnUplink != [ ]) {
              VLAN = map (
                transitName:
                let
                  transit = transitBridges.${transitName};
                in
                "${uplink.bridge}.${toString transit.vlan}"
              ) transitNamesOnUplink;
            };
        };
      }
    ) uplinkNames
  );

  transitNetdevs = builtins.listToAttrs (
    map (
      transitName:
      let
        transit = transitBridges.${transitName};
      in
      {
        name = "20-${transit.name}";
        value.netdevConfig = {
          Name = transit.name;
          Kind = "bridge";
        };
      }
    ) transitNames
  );

  transitNetworks = builtins.listToAttrs (
    lib.concatMap (
      transitName:
      let
        transit = transitBridges.${transitName};
        uplinkName = transit.parentUplink;
        uplink = uplinks.${uplinkName};
        transitVlanIfName = "${uplink.bridge}.${toString transit.vlan}";
      in
      [
        {
          name = "30-${transit.name}";
          value = {
            matchConfig.Name = transit.name;
            networkConfig.ConfigureWithoutCarrier = true;
          };
        }
      ]
      ++ lib.optionals (uplink.mode == "trunk") [
        {
          name = "31-${transitVlanIfName}";
          value = {
            matchConfig.Name = transitVlanIfName;
            networkConfig = {
              Bridge = transit.name;
              DHCP = "no";
              IPv6AcceptRA = false;
              ConfigureWithoutCarrier = true;
            };
          };
        }
      ]
    ) transitNames
  );
in
{
  netdevs = uplinkNetdevs // transitNetdevs;
  networks = uplinkParentNetworks // uplinkBridgeNetworks // transitNetworks;
}
