{ containerName, ... }:

let
  ifName = "${containerName}-wan";
in
{
  systemd.network.networks."10-${ifName}" = {
    matchConfig.Name = ifName;

    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = true;

      IPv4Forwarding = true;
      IPv6Forwarding = true;

      ConfigureWithoutCarrier = true;
    };
  };
}
