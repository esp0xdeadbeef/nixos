# FILE: container-router-access/node-from-topology.nix
{ ... }:
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
}

