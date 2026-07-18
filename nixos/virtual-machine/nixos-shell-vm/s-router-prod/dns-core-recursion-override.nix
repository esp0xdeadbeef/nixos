{ lib, outPath, ... }:

let
  dns = import "${outPath}/prod-network/s-router-prod/dns-runtime-addresses.nix";
in
{
  # TEMPORARY FS-540 SMS OVERRIDE:
  #
  # The pinned CPM treats the access DNS service-to-WAN compatibility
  # projection as if it were hosted on every DNS listener. On core this invents
  # public forwarders and broadens allowFrom, even though recursiveDnsIntent
  # assigns recursion to core and access points only at core. Keep this override
  # limited to the two affected Unbound fields. Routes, source-policy rules,
  # nftables handoffs, listeners, and access forwarders remain renderer-native.
  #
  # Remove this file when FS-540 scopes hosted DNS services to their provider
  # node and accepts the address-free service-origin contract without changing
  # unrelated IPv6 route materialization.
  containers.core.config.services.unbound.settings = {
    "forward-zone" = lib.mkForce [ ];

    server."access-control" = lib.mkForce [
      "127.0.0.0/8 allow"
      "::1/128 allow"
      "${dns.requesters.access-vlan2.clientIpv4} allow"
      "${dns.requesters.access-vlan2.clientIpv6} allow"
      "${dns.requesters.access-vlan7.ipv4}/32 allow"
      "${dns.requesters.access-vlan7.ipv6}/128 allow"
    ];
  };
}
