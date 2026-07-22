{ lib, relativeRepo, ... }:
let
  dns = import (relativeRepo.module "prod-network/current/dns-runtime-addresses.nix");
  prodInventory = import (relativeRepo.module "prod-network/current/inventory.nix");
  vlan3AuthorityRecords =
    prodInventory.realization.nodes."esp0xdeadbeef-site-a-access-vlan3".services.dns.localRecords;
  vlan3AuthorityNames = map (record: record.name) vlan3AuthorityRecords;
in
{
  # TEMPORARY NETWORK-* COMPATIBILITY OVERRIDE.
  #
  # The pinned local-sharing schema accepts only one requester/authority pair.
  # Keep the existing VLAN 3 -> VLAN 2 shared-lan lookup, but make VLAN 2 ask
  # VLAN 3 for this VLAN 3-owned name rather than copying its A/AAAA data into
  # the VLAN 2 resolver. VLAN 3's refuse_non_local ACL makes the handoff local
  # data-only and prevents recursion or transitive Internet access.
  #
  # Remove this file, its import, warning, and parity assertions once network-*
  # supports multiple directional relation-bound local namespace authorities
  # and derives publication from the modeled provider endpoint.
  containers.access-vlan2.config.services.unbound.settings = {
    server."local-zone" = lib.mkAfter (
      map (name: "${name} transparent") vlan3AuthorityNames
    );

    "forward-zone" = lib.mkAfter (
      map
        (name: {
          inherit name;
          "forward-addr" = [
            dns.requesters.access-vlan3.ipv4
            dns.requesters.access-vlan3.ipv6
          ];
          "forward-first" = false;
        })
        vlan3AuthorityNames
    );
  };
}
