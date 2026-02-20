{
  systemd.network.networks."10-wan" = {
    matchConfig.Name = "wan";

    networkConfig = {
      DHCP = "yes";
      IPv6AcceptRA = true;

      IPv4Forwarding = true;
      IPv6Forwarding = true;

      ConfigureWithoutCarrier = true;
    };
  };
}

