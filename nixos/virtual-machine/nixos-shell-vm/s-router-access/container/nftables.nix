{
  lib,
  ...
}:

{
  networking.nftables.enable = true;

  # Append; don't replace other modules' rulesets
  networking.nftables.ruleset = lib.mkAfter ''
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
