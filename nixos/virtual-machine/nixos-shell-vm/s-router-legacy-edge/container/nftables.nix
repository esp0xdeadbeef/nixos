### FILE: ./nftables.nix ###
{
  config,
  lib,
  args,
  ...
}:

let
  wans = args.wans or [ ];
  wanIfaces = map (w: w.iface) wans;

  # nft "define" set payload like: { "wan0", "ppp0" }
  wanSet = "{ " + (lib.concatStringsSep ", " (map (i: "\"${i}\"") wanIfaces)) + " }";
in
{
  networking.nftables.enable = true;

  networking.nftables.ruleset = ''
    #
    # IPv4 NAT (SNAT / masquerade) for LAN -> WAN
    #
    table ip nat {
      # WAN egress interfaces (from args.wans)
      define wan_ifaces = ${wanSet}

      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;

        # Masquerade anything that leaves via a WAN iface
        oifname $wan_ifaces masquerade
      }
    }

    #
    # Minimal filter (you currently allow basically everything)
    #
    table inet filter {
      chain input {
        type filter hook input priority 0; policy accept;
        ip6 nexthdr icmpv6 accept
      }

      chain forward {
        type filter hook forward priority 0; policy accept;
        ct state established,related accept
      }

      chain output {
        type filter hook output priority 0; policy accept;
      }
    }
  '';
}

