{ lib, pkgs, ... }:
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  # If you don't want wait-online blocking boot (common for routers)
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  systemd.network.networks."10-transit" = {
    matchConfig.Name = "lan1010"; # <-- adjust to your actual interface name

    networkConfig = {
      ConfigureWithoutCarrier = true;
      IPv6AcceptRA = true;

      # Transit IPv4
      Address = "10.255.255.2/30";
      Gateway = "10.255.255.1";

      # Optional: DNS if this box itself needs to resolve
      #DNS = [
      #  "1.1.1.1"
      #  "9.9.9.9"
      #];
    };
  };
}
