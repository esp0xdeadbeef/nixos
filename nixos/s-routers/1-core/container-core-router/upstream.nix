{ pkgs, lib, ... }:
{
  systemd.network.networks."10-lan1010-uplink" = {
    matchConfig.Name = "lan1010";

    networkConfig = {
      ConfigureWithoutCarrier = true;

      # IPv4 transit (keep this)
      #Address = "10.255.255.1/30";
      #Gateway = "10.255.255.1";

      IPv6AcceptRA = false;
      IPv6Forwarding = true;

      DHCP = "no";
    };

    addresses = [
      { Address = "10.255.255.1/30"; }
    ];
  };

}
