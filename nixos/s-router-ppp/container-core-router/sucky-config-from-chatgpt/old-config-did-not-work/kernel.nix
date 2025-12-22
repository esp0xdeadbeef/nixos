{ pkgs, lib, ... }:
{

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.default.forwarding" = 1;

    # Accept RA ONLY on ppp0
    # kernel does this automaticcly with systemd networking:
    #"net.ipv6.conf.all.accept_ra" = 0;
    #"net.ipv6.conf.ppp0.accept_ra" = 2;
    #"net.ipv6.conf.lan1010.accept_ra" = 0;

    # bridge safety
    "net.bridge.bridge-nf-call-ip6tables" = 0;
    "net.bridge.bridge-nf-call-iptables" = 0;
    "net.bridge.bridge-nf-call-arptables" = 0;
  };

}
