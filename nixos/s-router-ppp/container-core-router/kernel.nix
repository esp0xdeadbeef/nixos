{ pkgs, lib, ... }:
{

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;

    # accept RA from ppp0
    "net.ipv6.conf.ppp0.accept_ra" = 2;

    # IPv6 routing ON
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.default.forwarding" = 1;

    # REQUIRED for RA while forwarding
    "net.ipv6.conf.all.accept_ra" = 2;
    "net.ipv6.conf.default.accept_ra" = 2;

    # LAN interfaces MUST accept RA
    "net.ipv6.conf.lan2.accept_ra" = 2;
    "net.ipv6.conf.lan3.accept_ra" = 2;
    "net.ipv6.conf.lan10.accept_ra" = 2;
    "net.ipv6.conf.lan1000.accept_ra" = 2;
    "net.ipv6.conf.lan1010.accept_ra" = 2;

    # RA over bridges WILL NOT WORK without this
    "net.bridge.bridge-nf-call-ip6tables" = 0;
    "net.bridge.bridge-nf-call-iptables" = 0;
    "net.bridge.bridge-nf-call-arptables" = 0;
  };
}
