{
  config,
  lib,
  fabricCompiled,
  ...
}:

let
  inventoryImported = import ../inventory.nix;
  inventory =
    if builtins.isFunction inventoryImported then
      inventoryImported { inherit lib; }
    else
      inventoryImported;

  hostname = config.networking.hostName;

  deploymentHosts = inventory.deployment.host or {};
  hostConfig =
    if builtins.hasAttr hostname deploymentHosts then
      deploymentHosts.${hostname}
    else
      throw "host-network: missing host config";

  uplink = hostConfig.uplink;

  trunkParent =
    if uplink ? parent && builtins.isString uplink.parent then
      uplink.parent
    else
      throw "host-network: uplink.parent missing";

  mgmt =
    if uplink ? management && builtins.isAttrs uplink.management then
      uplink.management
    else
      throw "host-network: uplink.management missing";

  mgmtVlan =
    if mgmt ? vlan then mgmt.vlan else throw "host-network: management.vlan missing";

  mgmtBridge =
    if mgmt ? bridge then mgmt.bridge else throw "host-network: management.bridge missing";

  mgmtVlanIf = "${trunkParent}.${toString mgmtVlan}";

  wan =
    if uplink ? wan && builtins.isAttrs uplink.wan then
      uplink.wan
    else
      throw "host-network: uplink.wan missing";

  wanVlan =
    if wan ? vlan then wan.vlan else throw "host-network: uplink.wan.vlan missing";

  wanBridge =
    if wan ? bridge then wan.bridge else throw "host-network: uplink.wan.bridge missing";

  fabric =
    if uplink ? fabric && builtins.isAttrs uplink.fabric then
      uplink.fabric
    else
      throw "host-network: uplink.fabric missing";

  fabricVlan =
    if fabric ? vlan then fabric.vlan else throw "host-network: uplink.fabric.vlan missing";

  fabricBridge =
    if fabric ? bridge then fabric.bridge else throw "host-network: uplink.fabric.bridge missing";

  wanVlanIf = "${trunkParent}.${toString wanVlan}";
  fabricVlanIf = "${trunkParent}.${toString fabricVlan}";
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;

  systemd.network.netdevs = {
    "00-${mgmtBridge}" = {
      netdevConfig = {
        Name = mgmtBridge;
        Kind = "bridge";
      };
    };

    "01-${mgmtVlanIf}" = {
      netdevConfig = {
        Name = mgmtVlanIf;
        Kind = "vlan";
      };
      vlanConfig.Id = mgmtVlan;
    };

    "02-${wanBridge}" = {
      netdevConfig = {
        Name = wanBridge;
        Kind = "bridge";
      };
    };

    "03-${wanVlanIf}" = {
      netdevConfig = {
        Name = wanVlanIf;
        Kind = "vlan";
      };
      vlanConfig.Id = wanVlan;
    };

    "04-${fabricBridge}" = {
      netdevConfig = {
        Name = fabricBridge;
        Kind = "bridge";
      };
    };

    "05-${fabricVlanIf}" = {
      netdevConfig = {
        Name = fabricVlanIf;
        Kind = "vlan";
      };
      vlanConfig.Id = fabricVlan;
    };
  };

  systemd.network.networks = {
    "00-${trunkParent}" = {
      matchConfig.Name = trunkParent;
      networkConfig = {
        VLAN = [
          mgmtVlanIf
          wanVlanIf
          fabricVlanIf
        ];
        ConfigureWithoutCarrier = true;
      };
    };

    "05-${mgmtVlanIf}" = {
      matchConfig.Name = mgmtVlanIf;
      networkConfig = {
        Bridge = mgmtBridge;
        ConfigureWithoutCarrier = true;
      };
    };

    "06-${mgmtBridge}" = {
      matchConfig.Name = mgmtBridge;
      networkConfig = {
        DHCP = "ipv4";
        ConfigureWithoutCarrier = true;
      };
    };

    "10-${wanVlanIf}" = {
      matchConfig.Name = wanVlanIf;
      networkConfig = {
        Bridge = wanBridge;
        ConfigureWithoutCarrier = true;
      };
    };

    # FIX: no IP on host WAN bridge
    "11-${wanBridge}" = {
      matchConfig.Name = wanBridge;
      networkConfig = {
        LinkLocalAddressing = "no";
        IPv6AcceptRA = false;
        ConfigureWithoutCarrier = true;
      };
    };

    "20-${fabricVlanIf}" = {
      matchConfig.Name = fabricVlanIf;
      networkConfig = {
        Bridge = fabricBridge;
        ConfigureWithoutCarrier = true;
      };
    };

    "21-${fabricBridge}" = {
      matchConfig.Name = fabricBridge;
      networkConfig = {
        LinkLocalAddressing = "no";
        ConfigureWithoutCarrier = true;
      };
    };
  };
}
