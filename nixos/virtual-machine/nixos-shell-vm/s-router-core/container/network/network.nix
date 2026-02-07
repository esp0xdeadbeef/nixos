{ config, pkgs, lib, ... }:

let
  lanIf = "lan";
  wanIf = "wan";

  # LEGACY: do not touch
  natVlans = [ 1010 ];

  # ISP VLAN
  wanVlan = 6;

  mkVlanIf = base: vid: "${base}.${toString vid}";
in
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  ############################
  # Netdevs
  ############################
  systemd.network.netdevs = {
    "lan-vlan1010" = {
      netdevConfig = {
        Name = mkVlanIf lanIf 1010;
        Kind = "vlan";
      };
      vlanConfig.Id = 1010;
    };

    "br-vlan1010" = {
      netdevConfig = {
        Name = "br-vlan1010";
        Kind = "bridge";
      };
    };

    "wan-vlan6" = {
      netdevConfig = {
        Name = mkVlanIf wanIf 6;
        Kind = "vlan";
      };
      vlanConfig.Id = 6;
    };

    "br-wan6" = {
      netdevConfig = {
        Name = "br-wan6";
        Kind = "bridge";
      };
    };
  };

  ############################
  # Networks
  ############################
  systemd.network.networks = {

    # Physical LAN trunk
    "10-lan" = {
      matchConfig.Name = "lan";
      networkConfig = {
        DHCP = "no";
        VLAN = [ (mkVlanIf lanIf 1010) ];
      };
    };

    # LAN VLAN → bridge
    "20-lan1010" = {
      matchConfig.Name = mkVlanIf lanIf 1010;
      networkConfig.Bridge = "br-vlan1010";
    };

    # Legacy bridge (Kea lives here)
    "30-br-vlan1010" = {
      matchConfig.Name = "br-vlan1010";
      networkConfig = {
        ConfigureWithoutCarrier = true;
        IPv6AcceptRA = false;
      };
    };

    # Physical WAN trunk
    "40-wan" = {
      matchConfig.Name = "wan";
      networkConfig = {
        DHCP = "no";
        VLAN = [ (mkVlanIf wanIf 6) ];
      };
    };

    # 🔥 THIS WAS MISSING 🔥
    # VLAN MUST BE ENSLAVED INTO THE BRIDGE
    "50-wan6-slave" = {
      matchConfig.Name = mkVlanIf wanIf 6;
      networkConfig = {
        Bridge = "br-wan6";
      };
    };

    # WAN bridge (PPPoE attaches here)
    "60-br-wan6" = {
      matchConfig.Name = "br-wan6";
      networkConfig = {
        ConfigureWithoutCarrier = true;
      };
    };
  };
}

