# Cobalt site DNS runtime addresses (IPv4-only).
# Keep distinct from prod-network/current/dns-runtime-addresses.nix so the
# combined inventory can index endpoints without address collisions.
{
  resolver = {
    node = "core";
    service = "core-dns";
    ipv4 = "10.1.0.8";
  };

  requesters = {
    access-vlan2 = {
      ipv4 = "10.2.2.1";
      clientIpv4 = "10.2.2.0/24";
    };

    access-vlan3 = {
      ipv4 = "10.2.3.1";
      clientIpv4 = "10.2.3.0/24";
    };

    access-vlan7 = {
      ipv4 = "10.2.7.1";
      clientIpv4 = "10.2.7.0/24";
    };

    access-vlan8 = {
      ipv4 = "10.2.8.1";
      clientIpv4 = "10.2.8.0/24";
    };
  };
}
