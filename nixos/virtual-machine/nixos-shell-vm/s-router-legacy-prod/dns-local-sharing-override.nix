{ lib, outPath, ... }:

let
  dns = import "${outPath}/prod-network/legacy/dns-runtime-addresses.nix";
  vlan2 = dns.requesters.access-vlan2;
  vlan3 = dns.requesters.access-vlan3;
in
{
  # TEMPORARY FS-540 LOCAL-NAMESPACE SMS OVERRIDE:
  #
  # The active service-to-service intent renders the access-vlan3 ->
  # access-vlan2 routes and nftables handoffs. The pinned renderer cannot yet
  # express named forward zones or Unbound's refuse_non_local ACL action.
  # Keep this override limited to those resolver semantics.
  #
  # VLAN 3 resolves its own local-data first, forwards only VLAN 2's lan.
  # namespaces to access-vlan2, and answers every other namespace from the
  # static root zone. It therefore cannot recurse to core or the Internet.
  containers.access-vlan3.config.services.unbound.settings = {
    server = {
      "access-control" = lib.mkForce [
        "127.0.0.0/8 allow"
        "::1/128 allow"
        "${vlan3.clientIpv4} allow"
        "${vlan3.clientIpv6} allow"
        "${vlan2.clientIpv4} refuse_non_local"
        "${vlan2.clientIpv6} refuse_non_local"
      ];

      "local-zone" = lib.mkForce [
        ". static"
        "lan. transparent"
        "1.168.192.in-addr.arpa. transparent"
      ];
    };

    "forward-zone" = lib.mkForce [
      {
        name = "lan.";
        "forward-addr" = [
          vlan2.ipv4
          vlan2.ipv6
        ];
        "forward-first" = false;
      }
      {
        name = "1.168.192.in-addr.arpa.";
        "forward-addr" = [
          vlan2.ipv4
          vlan2.ipv6
        ];
        "forward-first" = false;
      }
    ];
  };

  # VLAN 2 clients retain recursion through core. The VLAN 3 resolver source is
  # deliberately local-data-only, so even a query outside the forwarded zones
  # is refused rather than recursively resolved through VLAN 2.
  containers.access-vlan2.config.services.unbound.settings.server."access-control" = lib.mkForce [
    "127.0.0.0/8 allow"
    "::1/128 allow"
    "${vlan2.clientIpv4} allow"
    "${vlan2.clientIpv6} allow"
    "${vlan3.ipv4}/32 refuse_non_local"
    "${vlan3.ipv6}/128 refuse_non_local"
  ];

}
