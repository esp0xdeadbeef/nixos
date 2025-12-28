{ config, pkgs, lib, ... }:

{
  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network = {
    enable = true;

    netdevs."br-isp-0" = {
      netdevConfig = {
        Name = "br-isp-0";
        Kind = "bridge";
      };
    };

    netdevs."br-isp-dummy" = {
      netdevConfig = {
        Name = "br-isp-dummy";
        Kind = "dummy";
      };
    };

    networks."br-isp-dummy" = {
      matchConfig.Name = "br-isp-dummy";
      networkConfig = {
        Bridge = "br-isp-0";
      };
    };

    networks."ens20" = {
      matchConfig.Name = "ens20";
      networkConfig = {
        Bridge = "br-isp-0";
        DHCP = "no";
        LinkLocalAddressing = "no";
      };
    };

    networks."br-isp-0" = {
      matchConfig.Name = "br-isp-0";
      networkConfig = {
        DHCP = "no";
        LinkLocalAddressing = "no";
        ConfigureWithoutCarrier = true;
      };
    };
  };
}

