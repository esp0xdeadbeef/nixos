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
      {
        Address = "10.255.255.1/29";
      }
      {
        Address = "fd42:dead:beef:100::1/64";
      }
    ];
    routes = [
      {

          Destination = "10.13.37.0/24";
          Gateway = "10.255.255.2";
      }
      {
          Destination = "10.10.3.0/24";
          Gateway = "10.255.255.2";
      }
      {
          Destination = "192.168.1.0/24";
          Gateway = "10.255.255.2";
      }
      {
          Destination = "10.10.0.0/16";
          Gateway = "10.255.255.2";
      }
    ];

  };
}
