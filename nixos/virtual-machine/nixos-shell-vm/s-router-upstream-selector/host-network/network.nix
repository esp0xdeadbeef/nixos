{
  config,
  lib,
  ...
}:

let
  inventory = import ../inventory.nix;

  hostName = config.networking.hostName;

  hostDeployment =
    if inventory ? deployment
      && inventory.deployment ? host
      && builtins.hasAttr hostName inventory.deployment.host
    then
      inventory.deployment.host.${hostName}
    else
      throw "host-network/network.nix: missing deployment.host.${hostName}";

  uplink =
    if hostDeployment ? uplink && builtins.isAttrs hostDeployment.uplink then
      hostDeployment.uplink
    else
      throw "host-network/network.nix: missing deployment.host.${hostName}.uplink";

  parentIf =
    if uplink ? parent && uplink.parent != "" then
      uplink.parent
    else
      throw "host-network/network.nix: missing deployment.host.${hostName}.uplink.parent";

  fabricNode =
    if inventory ? fabric && builtins.hasAttr hostName inventory.fabric then
      inventory.fabric.${hostName}
    else
      throw "host-network/network.nix: missing fabric.${hostName}";

  ports =
    if fabricNode ? ports && builtins.isAttrs fabricNode.ports then
      fabricNode.ports
    else
      throw "host-network/network.nix: missing fabric.${hostName}.ports";

  portNames = lib.sort builtins.lessThan (builtins.attrNames ports);

  transitVlans =
    lib.sort builtins.lessThan (
      lib.unique (
        map (
          portName:
          let
            port = ports.${portName};
          in
          if port ? vlan then
            port.vlan
          else
            throw "host-network/network.nix: missing vlan on fabric.${hostName}.ports.${portName}"
        ) portNames
      )
    );

  trunkBridgeName = "br-fabric";
  transitBridgeName = vlan: "tr${toString vlan}";
  trunkVlanIfName = vlan: "${trunkBridgeName}.${toString vlan}";
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  systemd.network.netdevs =
    {
      "10-${trunkBridgeName}" = {
        netdevConfig = {
          Name = trunkBridgeName;
          Kind = "bridge";
        };
      };
    }
    // builtins.listToAttrs (
      map (
        vlan:
        {
          name = "11-${trunkVlanIfName vlan}";
          value = {
            netdevConfig = {
              Name = trunkVlanIfName vlan;
              Kind = "vlan";
            };
            vlanConfig.Id = vlan;
          };
        }
      ) transitVlans
    )
    // builtins.listToAttrs (
      map (
        vlan:
        {
          name = "20-${transitBridgeName vlan}";
          value = {
            netdevConfig = {
              Name = transitBridgeName vlan;
              Kind = "bridge";
            };
          };
        }
      ) transitVlans
    );

  systemd.network.networks =
    {
      "05-${parentIf}" = {
        matchConfig.Name = parentIf;
        networkConfig = {
          Bridge = trunkBridgeName;
          DHCP = "no";
          IPv6AcceptRA = false;
          ConfigureWithoutCarrier = true;
        };
      };

      "06-${trunkBridgeName}" = {
        matchConfig.Name = trunkBridgeName;
        networkConfig = {
          VLAN = map trunkVlanIfName transitVlans;
          ConfigureWithoutCarrier = true;
        };
      };
    }
    // builtins.listToAttrs (
      lib.concatMap (
        vlan:
        [
          {
            name = "30-${trunkVlanIfName vlan}";
            value = {
              matchConfig.Name = trunkVlanIfName vlan;
              networkConfig = {
                Bridge = transitBridgeName vlan;
                DHCP = "no";
                IPv6AcceptRA = false;
                ConfigureWithoutCarrier = true;
              };
            };
          }
          {
            name = "31-${transitBridgeName vlan}";
            value = {
              matchConfig.Name = transitBridgeName vlan;
              networkConfig = {
                ConfigureWithoutCarrier = true;
              };
            };
          }
        ]
      ) transitVlans
    );
}
