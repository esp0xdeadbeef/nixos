{ config, pkgs, lib, ... }:

{
  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network = {
    enable = true;

    netdevs."br-lan-0" = {
      netdevConfig = {
        Name = "br-lan-0";
        Kind = "bridge";
      };
    };

    netdevs."br-lan-dummy" = {
      netdevConfig = {
        Name = "br-lan-dummy";
        Kind = "dummy";
      };
    };

    networks."br-lan-dummy" = {
      matchConfig.Name = "br-lan-dummy";
      networkConfig = {
        Bridge = "br-lan-0";
      };
    };

    networks."ens21" = {
      matchConfig.Name = "ens21";
      networkConfig = {
        Bridge = "br-lan-0";
        DHCP = "no";
        LinkLocalAddressing = "no";
      };
    };

    networks."br-lan-0" = {
      matchConfig.Name = "br-lan-0";
      networkConfig = {
        DHCP = "no";
        LinkLocalAddressing = "no";
        ConfigureWithoutCarrier = true;
      };
    };
  };
}

