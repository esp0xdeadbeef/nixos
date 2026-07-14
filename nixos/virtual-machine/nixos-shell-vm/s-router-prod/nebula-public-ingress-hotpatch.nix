{ lib, ... }:

{
  # Temporary until network-renderer-nixos materializes
  # publicIngressTupleAuthority as core-owned DNAT.
  containers.core.config.networking.nftables.ruleset = lib.mkAfter ''
    table ip s_router_prod_nebula_hotpatch {
      chain prerouting {
        type nat hook prerouting priority -101; policy accept;
        iifname "ppp0" udp dport 4242 counter dnat to 192.168.3.10:4242 comment "hotpatch-nebula-public-ingress-udp"
        iifname "ppp0" tcp dport 4242 counter dnat to 192.168.3.10:4242 comment "hotpatch-nebula-public-ingress-tcp"
      }
    }
  '';
}
