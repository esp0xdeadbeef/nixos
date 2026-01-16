{ pkgs, lib, ... }:
{

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;

    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.default.forwarding" = 1;

    # Router defaults: don't accept RA globally
    "net.ipv6.conf.all.accept_ra" = 0;
    "net.ipv6.conf.default.accept_ra" = 0;

    # Only uplink should accept RA
    "net.ipv6.conf.lan1010.accept_ra" = 2;

    # LANs should NOT accept RA
    "net.ipv6.conf.lan2.accept_ra" = 0;
    "net.ipv6.conf.lan3.accept_ra" = 0;
    "net.ipv6.conf.lan7.accept_ra" = 0;
    "net.ipv6.conf.lan10.accept_ra" = 0;
    "net.ipv6.conf.lan1000.accept_ra" = 0;

    # Your bridge sysctls are fine to keep
    "net.bridge.bridge-nf-call-ip6tables" = 0;
    "net.bridge.bridge-nf-call-iptables" = 0;
    "net.bridge.bridge-nf-call-arptables" = 0;
  };

}
