{ pkgs, lib, ... }:
{
  systemd.network.networks."20-lan1010" = {
    matchConfig.Name = "lan1010";

    networkConfig = {
      ConfigureWithoutCarrier = true;

      IPv6SendRA = true;
      IPv6AcceptRA = false;
      IPv6Forwarding = true;
    };

    ipv6Prefixes = [
      { Prefix = "::/64"; }
    ];

    addresses = [
      { Address = "10.255.255.1/30"; }
    ];
  };

}
