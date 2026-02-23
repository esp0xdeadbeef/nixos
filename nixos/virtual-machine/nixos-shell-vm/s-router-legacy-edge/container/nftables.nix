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
    table ip nat {
      define wan_ifaces = ${wanSet}
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname $wan_ifaces masquerade
      }
    }

    table inet filter {
      define wan_ifaces = ${wanSet}

      chain input {
        type filter hook input priority 0;
        policy drop;

        iif lo accept
        ct state established,related accept
        ct state invalid drop

        # IPv6 ND etc.
        ip6 nexthdr icmpv6 accept

        # Anti-spoof on WAN
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

        iifname $wan_ifaces ip6 saddr {
          ::1,
          fc00::/7,
          fe80::/10
        } drop

        # allow mgmt from inside
        iifname != $wan_ifaces tcp dport 22 accept

        # if you run DNS/DHCP on this box and want LAN clients to reach it:
        iifname != $wan_ifaces udp dport { 53, 67 } accept
        iifname != $wan_ifaces tcp dport 53 accept
      }

      chain forward {
        type filter hook forward priority 0;
        policy accept;

        ct state established,related accept
        ct state invalid drop

        # Anti-spoof on WAN ingress
        iifname $wan_ifaces ip saddr {
          10.0.0.0/8,
          172.16.0.0/12,
          192.168.0.0/16,
          100.64.0.0/10
        } drop

        iifname $wan_ifaces ip6 saddr fc00::/7 drop
      }

      chain output {
        type filter hook output priority 0;
        policy accept;
      }
    }
  '';
}
