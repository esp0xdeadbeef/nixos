{
  config,
  pkgs,
  lib,
  ...
}:

{
  /**
    ******************************************************************
     GLOBAL
    ******************************************************************
  */
  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network.enable = true;
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  /**
    ******************************************************************
     NETDEVS (BRIDGES)
    ******************************************************************
  */
  systemd.network.netdevs = {
    "10-vmbr0" = {
      netdevConfig = {
        Name = "vmbr0";
        Kind = "bridge";
      };
    };
  };

  /**
    ******************************************************************
     NETWORKS
    ******************************************************************
  */
  systemd.network.networks = {

    /**
      ****************** MGMT (UNTOUCHED) ***************************
    */
    "10-eno4" = {
      matchConfig.Name = "eno4";
      networkConfig = {
        Bridge = "vmbr0";
        DHCP = "no";
        LinkLocalAddressing = "no";
      };
    };

    "20-vmbr0" = {
      matchConfig.Name = "vmbr0";
      networkConfig = {
        DHCP = "ipv4";
        ConfigureWithoutCarrier = true;
        LinkLocalAddressing = "no";
      };

      dhcpV4Config = {
        ClientIdentifier = "mac";
        SendRelease = false;
        MaxAttempts = 0;
        UseRoutes = true;
        UseGateway = true;
      };

      extraConfig = ''
        [DHCPv4]
        KeepConfiguration=yes
      '';
    };

  };

}
