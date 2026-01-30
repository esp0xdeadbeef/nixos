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
  };
}

