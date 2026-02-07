{ pkgs, lib, ... }:
{
  boot.kernel.sysctl = {
    # Router
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.default.forwarding" = 1;

    # Accept RA ONLY from ISP
    "net.ipv6.conf.all.accept_ra" = 0;
    "net.ipv6.conf.ppp0.accept_ra" = 2;

    # NO SLAAC / auto addresses anywhere
    "net.ipv6.conf.all.autoconf" = 0;
    "net.ipv6.conf.default.autoconf" = 0;

    # Stable router addresses (FORCE override container defaults)
    "net.ipv6.conf.all.use_tempaddr" = lib.mkForce 0;
    "net.ipv6.conf.default.use_tempaddr" = lib.mkForce 0;

    # Bridge safety (L2 stays L2)
    "net.bridge.bridge-nf-call-ip6tables" = 0;
    "net.bridge.bridge-nf-call-iptables" = 0;
    "net.bridge.bridge-nf-call-arptables" = 0;
  };
}
