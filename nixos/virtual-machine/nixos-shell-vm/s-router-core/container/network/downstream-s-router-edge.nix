{ lib, ... }:
{
  systemd.network.networks."10-transit100" = {
    matchConfig.Name = "br-transit100";
    networkConfig = {
      ConfigureWithoutCarrier = true;
      DHCP = "no";
    };
    addresses = [
      { Address = "10.100.0.2/31"; } # example
    ];
  };

}
