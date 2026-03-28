{ lib, ... }:

{
  networking.useNetworkd = lib.mkDefault true;
  systemd.network.enable = lib.mkDefault true;

  systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";

  systemd.network.netdevs."05-eth1.2" = {
    netdevConfig = {
      Name = "eth1.2";
      Kind = "vlan";
    };

    extraConfig = ''
      [VLAN]
      Id=2
    '';
  };

  systemd.network.networks."04-eth0" = {
    matchConfig = {
      Name = "eth0";
    };

    linkConfig = {
      ActivationPolicy = "always-up";
      RequiredForOnline = "no";
    };

    networkConfig = {
      DHCP = "ipv4";
      ConfigureWithoutCarrier = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
    };

    extraConfig = ''
      [DHCPv4]
      ClientIdentifier=mac
      RequestBroadcast=yes
      UseRoutes=yes
      UseDNS=yes
      RouteMetric=50
    '';
  };

  systemd.network.networks."05-eth1" = {
    matchConfig = {
      Name = "eth1";
    };

    linkConfig = {
      ActivationPolicy = "always-up";
      RequiredForOnline = "no";
    };

    networkConfig = {
      ConfigureWithoutCarrier = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
      VLAN = [ "eth1.2" ];
    };
  };

  systemd.network.networks."06-eth1.2" = {
    matchConfig = {
      Name = "eth1.2";
    };

    linkConfig = {
      ActivationPolicy = "always-up";
      RequiredForOnline = "no";
    };

    networkConfig = {
      DHCP = "ipv4";
      ConfigureWithoutCarrier = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
    };

    extraConfig = ''
      [DHCPv4]
      ClientIdentifier=mac
      RequestBroadcast=yes
      UseRoutes=no
      UseDNS=no
      RouteMetric=4096
    '';
  };
}
