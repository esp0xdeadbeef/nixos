{
  config,
  lib,
  args,
  ...
}:

let
  wans = args.wans or [ ];
  wanIfaces = map (w: w.iface) wans;

  wanSet =
    if wanIfaces == [ ]
    then "{ }"
    else "{ " + (lib.concatStringsSep ", " (map (i: "\"${i}\"") wanIfaces)) + " }";

in
{
  networking.nftables.enable = true;

  networking.nftables.ruleset = ''

    ############################
    # NAT (IPv4 only)
    ############################
    table ip nat {
      define wan_ifaces = ${wanSet}

      chain postrouting {
        type nat hook postrouting priority srcnat;
        policy accept;

        oifname $wan_ifaces masquerade
      }
    }

    ############################
    # FILTER (CORE BASELINE)
    ############################
    table inet filter {

      define wan_ifaces = ${wanSet}

      #
      # INPUT (to router)
      #
      chain input {
        type filter hook input priority 0;
        policy drop;

        iif lo accept
        ct state established,related accept
        ct state invalid drop

        # ICMPv6 required for ND
        ip6 nexthdr icmpv6 accept

        # Anti-spoof IPv4
        iifname $wan_ifaces ip saddr {
          0.0.0.0/8,
          10.0.0.0/8,
          127.0.0.0/8,
          169.254.0.0/16,
          172.16.0.0/12,
          192.168.0.0/16,
          224.0.0.0/4,
          240.0.0.0/4
        } drop

        # Anti-spoof IPv6
        iifname $wan_ifaces ip6 saddr {
          ::1,
          fc00::/7,
          fe80::/10
        } drop

        # Allow LAN management (optional)
        iifname != $wan_ifaces tcp dport 22 accept
      }

      #
      # FORWARD (routing)
      #
      chain forward {
        type filter hook forward priority 0;
        policy drop;

        ct state established,related accept
        ct state invalid drop

        # Anti-spoof on WAN ingress
        iifname $wan_ifaces ip saddr {
          10.0.0.0/8,
          172.16.0.0/12,
          192.168.0.0/16
        } drop

        iifname $wan_ifaces ip6 saddr fc00::/7 drop

        # LAN -> WAN
        iifname != $wan_ifaces oifname $wan_ifaces accept

        # NAT ingress rules will be inserted by DSL later
      }

      chain output {
        type filter hook output priority 0;
        policy accept;
      }
    }
  '';

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.rp_filter" = 1;
  };
}
