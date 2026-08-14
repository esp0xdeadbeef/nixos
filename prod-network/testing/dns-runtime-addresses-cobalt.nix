# Cobalt site DNS runtime addresses.
# IPv4-only WAN (DHCP on VLAN 300, no public PD). The access fabric still
# carries ULA IPv6 internally because the pinned network stack requires
# IPv6 router-advertisement data on access nodes.
# Keep distinct from prod-network/current/dns-runtime-addresses.nix so the
# combined inventory can index endpoints without address collisions.
{
  resolver = {
    node = "core";
    service = "core-dns";
    ipv4 = "10.1.0.8";
    ipv6 = "fd42:dead:beef:2900::8";
  };

  requesters = {
    access-vlan2 = {
      ipv4 = "10.2.2.1";
      ipv6 = "fd42:dead:beef:c2::1";
      clientIpv4 = "10.2.2.0/24";
      clientIpv6 = "fd42:dead:beef:c2::/64";
    };

    access-vlan3 = {
      ipv4 = "10.2.3.1";
      ipv6 = "fd42:dead:beef:c3::1";
      clientIpv4 = "10.2.3.0/24";
      clientIpv6 = "fd42:dead:beef:c3::/64";
    };

    access-vlan7 = {
      ipv4 = "10.2.7.1";
      ipv6 = "fd42:dead:beef:c7::1";
      clientIpv4 = "10.2.7.0/24";
      clientIpv6 = "fd42:dead:beef:c7::/64";
    };

    access-vlan8 = {
      ipv4 = "10.2.8.1";
      ipv6 = "fd42:dead:beef:c8::1";
      clientIpv4 = "10.2.8.0/24";
      clientIpv6 = "fd42:dead:beef:c8::/64";
    };
  };
}
