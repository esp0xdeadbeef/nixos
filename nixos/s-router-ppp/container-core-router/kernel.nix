{ pkgs, lib, ... }:
{

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.default.forwarding" = 1;

    # Don't accept RA globally on a router
    "net.ipv6.conf.all.accept_ra" = 0;
    "net.ipv6.conf.default.accept_ra" = 0;

    # But DO accept RA on the PPPoE WAN interface if ISP uses RA (common)
    "net.ipv6.conf.ppp0.accept_ra" = 2;

    # On the transit LAN, do NOT accept RA (your real firewall will be the router there)
    "net.ipv6.conf.lan1010.accept_ra" = 0;
  };
}
