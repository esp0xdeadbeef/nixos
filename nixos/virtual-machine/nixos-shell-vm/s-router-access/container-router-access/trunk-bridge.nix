# ./container-router-access/trunk-bridge.nix
# FILE: container-router-access/trunk-bridge.nix
{ ... }:

{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  systemd.network.netdevs = {
    "10-br-lan-trunk" = {
      netdevConfig = {
        Name = "br-lan-trunk";
        Kind = "bridge";
      };
    };
  };

  systemd.network.networks = {
    # LAN trunk is eth0
    "10-uplink-lan" = {
      matchConfig.Name = "eth0";
      networkConfig.Bridge = "br-lan-trunk";
    };

    "20-br-lan-trunk" = {
      matchConfig.Name = "br-lan-trunk";
      networkConfig.ConfigureWithoutCarrier = true;
    };
  };
}

