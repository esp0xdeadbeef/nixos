{
  config,
  pkgs,
  lib,
  ...
}:

let
  lanIf = "lan";
  wanIf = "wan";
  natVlans = [ 1010 ];
  wanVlan = 6;
in
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  systemd.network.netdevs = {
    "10-lan-vlan1010" = {
      netdevConfig = {
        Name = "lan.1010";
        Kind = "vlan";
      };
      vlanConfig.Id = 1010;
    };

    "20-br-vlan1010" = {
      netdevConfig = {
        Name = "br-vlan1010";
        Kind = "bridge";
      };
    };

    "30-wan-vlan6" = {
      netdevConfig = {
        Name = "wan.6";
        Kind = "vlan";
      };
      vlanConfig.Id = 6;
    };

    "40-br-wan6" = {
      netdevConfig = {
        Name = "br-wan6";
        Kind = "bridge";
      };
    };
  };

  systemd.network.networks = {
    "10-lan" = {
      matchConfig.Name = "lan";
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "ipv6";
        VLAN = [ "lan.1010" ];
      };
    };

    "20-lan1010" = {
      matchConfig.Name = "lan.1010";
      networkConfig = {
        Bridge = "br-vlan1010";
        IPv6AcceptRA = false;
      };
    };

    "30-br-vlan1010" = {
      matchConfig.Name = "br-vlan1010";
      networkConfig = {
        ConfigureWithoutCarrier = true;
        IPv6AcceptRA = false;
      };
    };

    "40-wan" = {
      matchConfig.Name = "wan";
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "ipv6";
        VLAN = [ "wan.6" ];
      };
    };

    "50-wan6" = {
      matchConfig.Name = "wan.6";
      networkConfig.Bridge = "br-wan6";
    };

    "60-br-wan6" = {
      matchConfig.Name = "br-wan6";
      networkConfig.ConfigureWithoutCarrier = true;
    };
  };
}
