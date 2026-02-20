{
  systemd.network.networks."20-fabric" = {
    matchConfig.Name = "lan";

    addresses = [
      { Address = "10.255.0.1/31"; }
      { Address = "fd42:dead:beef:200::1/127"; }
    ];

    networkConfig = {
      IPv4Forwarding = true;
      IPv6Forwarding = true;
      ConfigureWithoutCarrier = true;
    };
  };
}

