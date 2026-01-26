{ lib, args }:
{ ... }:

let
  lanIfaces = map (l: l.iface) args.lans;
  lanSet = lib.concatStringsSep ", " (map (x: "\"${x}\"") lanIfaces);
in
{
  networking.nftables.enable = true;
  networking.nftables.ruleset = ''
    table inet filter {
      set lanifs { type ifname; elements = { ${lanSet} } }

      chain input {
        type filter hook input priority 0; policy drop;
        iif lo accept
        ct state established,related accept
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        iifname @lanifs udp dport 67 accept
      }

      chain forward {
        type filter hook forward priority 0; policy drop;
        ct state established,related accept
        iifname @lanifs meta mark set 0x1
        iifname @lanifs oifname "${args.wan.iface}" meta mark 0x1 accept
      }
    }

    table ip nat {
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "${args.wan.iface}" meta mark 0x1 masquerade
      }
    }
  '';
}
