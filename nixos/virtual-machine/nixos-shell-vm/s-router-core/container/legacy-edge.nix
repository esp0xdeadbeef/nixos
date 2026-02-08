{ pkgs, lib, ... }:
{
  systemd.network.networks."10-lan1010-uplink" = {
    matchConfig.Name = "br-gl-86d9";

    networkConfig = {
      ConfigureWithoutCarrier = true;
      DHCP = "no";
      IPv6AcceptRA = false;

      # you are routing on this box
      IPv6Forwarding = true;

      LinkLocalAddressing = "ipv6";
    };

    addresses = [
      { Address = "10.255.255.1/29"; }
    ];

    routes = [
      {
        Destination = "192.168.1.0/24";
        Gateway = "10.255.255.3";
      }
      {
        Destination = "192.168.2.0/24";
        Gateway = "10.255.255.3";
      }
    ];
  };
}

