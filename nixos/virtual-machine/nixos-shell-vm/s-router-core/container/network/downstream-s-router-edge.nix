{ pkgs, lib, ... }:
{
  systemd.network.networks."10-lan1010-uplink" = {
    matchConfig.Name = "br-vlan1010";

    networkConfig = {
      ConfigureWithoutCarrier = true;
      DHCP = "no";

      IPv6AcceptRA = false;
      IPv6Forwarding = true;
    };

    addresses = [
      { Address = "10.255.255.1/29"; }
    ];
    routes = [
      {
        routeConfig = {
          Destination = "10.13.37.0/24";
          Gateway = "10.255.255.2";
        };
      }
      {
        routeConfig = {
          Destination = "10.10.3.0/24";
          Gateway = "10.255.255.2";
        };
      }
      {
        routeConfig = {
          Destination = "192.168.1.0/24";
          Gateway = "10.255.255.2";
        };
      }
    ];

  };
}
