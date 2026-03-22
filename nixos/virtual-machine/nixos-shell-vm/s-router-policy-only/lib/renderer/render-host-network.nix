{
  lib,
  inventory,
  hostName,
  cpm ? null,
}:

let
  validated = import ./validate-realization.nix {
    inherit
      lib
      inventory
      hostName
      cpm
      ;
  };

  host = validated.deployment.hosts.${hostName};

  uplinks = host.uplinks;
  uplinkNames = builtins.attrNames uplinks;

  bridgeNetworkFor =
    bridge:
    if host ? bridgeNetworks && builtins.hasAttr bridge host.bridgeNetworks then
      host.bridgeNetworks.${bridge}
    else
      { ConfigureWithoutCarrier = true; };

  vlanIfNameFor =
    uplink:
    "${uplink.parent}.${toString uplink.vlan}";

  uplinkNetdevs = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
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
          name = "11-${vlanIfNameFor uplink}";
          value = {
            netdevConfig = {
              Name = vlanIfNameFor uplink;
              Kind = "vlan";
            };
            vlanConfig.Id = uplink.vlan;
          };
        }
      ]
    ) uplinkNames
  );

  uplinkParentNetworks = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
      in
      if uplink.mode == "vlan" then
        [
          {
            name = "05-${uplink.parent}";
            value = {
              matchConfig.Name = uplink.parent;
              networkConfig = {
                VLAN = [ (vlanIfNameFor uplink) ];
                DHCP = "no";
                IPv6AcceptRA = false;
                ConfigureWithoutCarrier = true;
              };
            };
          }
          {
            name = "05-${vlanIfNameFor uplink}";
            value = {
              matchConfig.Name = vlanIfNameFor uplink;
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
      in
      {
        name = "06-${uplink.bridge}";
        value = {
          matchConfig.Name = uplink.bridge;
          networkConfig = bridgeNetwork;
        };
      }
    ) uplinkNames
  );

  transitBridges =
    if host ? transitBridges && builtins.isAttrs host.transitBridges then
      host.transitBridges
    else
      { };

  transitNames = builtins.attrNames transitBridges;

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
    map (
      transitName:
      let
        transit = transitBridges.${transitName};
      in
      {
        name = "30-${transit.name}";
        value = {
          matchConfig.Name = transit.name;
          networkConfig.ConfigureWithoutCarrier = true;
        };
      }
    ) transitNames
  );
in
{
  netdevs = uplinkNetdevs // transitNetdevs;
  networks = uplinkParentNetworks // uplinkBridgeNetworks // transitNetworks;
}
