{
  pkgs,
  lib,
  helpers,
  args,
}:
{ config, ... }:

let
  inherit (args) wan lans;
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  systemd.network.networks =
    lib.listToAttrs (
      map (l: {
        name = "20-${l.name}-${l.iface}";
        value.matchConfig.Name = l.iface;
        value.networkConfig = {
          Address = [
            l.ip4
            l.ip6
          ];
          DHCP = "no";
          IPv6AcceptRA = false;
          IPv6Forwarding = true;
        };
      }) lans
    )
    // {
      "10-wan-${wan.iface}" = {
        matchConfig.Name = wan.iface;
        networkConfig = {
          Address = [
            wan.ip4
            wan.ip6
          ];
          Gateway = [
            wan.gw4
            wan.gw6
          ];
          DHCP = "no";
          IPv6AcceptRA = wan.acceptRA or false;
          IPv6Forwarding = true;
        };
      };
    };
}
