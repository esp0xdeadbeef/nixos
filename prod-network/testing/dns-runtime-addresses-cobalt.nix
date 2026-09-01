# Cobalt site DNS runtime addresses.
# IPv4-only WAN (DHCP on VLAN 300, no public PD). The access fabric still
# carries ULA IPv6 internally because the pinned network stack requires
# IPv6 router-advertisement data on access nodes.
# The cobalt site uses a distinct ULA/loopback allocation from the neon site,
# so the combined inventory can index endpoints without collisions.
{
  resolver = {
    node = "core";
    service = "core-dns";
    ipv4 = "10.1.0.8";
    ipv6 = "fd42:dead:beef:2900::8";
  };

  requesters = {
    access-svc = {
      ipv4 = "10.2.20.1";
      ipv6 = "fd42:dead:beef:220::1";
      clientIpv4 = "10.2.20.0/24";
      clientIpv6 = "fd42:dead:beef:220::/64";
    };

    access-clients = {
      ipv4 = "10.2.30.1";
      ipv6 = "fd42:dead:beef:230::1";
      clientIpv4 = "10.2.30.0/24";
      clientIpv6 = "fd42:dead:beef:230::/64";
    };

    access-dmz = {
      ipv4 = "10.2.60.1";
      ipv6 = "fd42:dead:beef:260::1";
      clientIpv4 = "10.2.60.0/24";
      clientIpv6 = "fd42:dead:beef:260::/64";
    };

    access-iot-srv = {
      ipv4 = "10.2.51.1";
      ipv6 = "fd42:dead:beef:251::1";
      clientIpv4 = "10.2.51.0/24";
      clientIpv6 = "fd42:dead:beef:251::/64";
    };

    access-iot = {
      ipv4 = "10.2.50.1";
      ipv6 = "fd42:dead:beef:250::1";
      clientIpv4 = "10.2.50.0/24";
      clientIpv6 = "fd42:dead:beef:250::/64";
    };

    access-clients-vpn = {
      ipv4 = "10.2.31.1";
      ipv6 = "fd42:dead:beef:231::1";
      clientIpv4 = "10.2.31.0/24";
      clientIpv6 = "fd42:dead:beef:231::/64";
    };

    access-unlock = {
      ipv4 = "10.2.90.1";
      ipv6 = "fd42:dead:beef:290::1";
      clientIpv4 = "10.2.90.0/24";
      clientIpv6 = "fd42:dead:beef:290::/64";
    };

    access-mgmt = {
      ipv4 = "10.2.10.1";
      ipv6 = "fd42:dead:beef:210::1";
      clientIpv4 = "10.2.10.0/24";
      clientIpv6 = "fd42:dead:beef:210::/64";
    };
  };
}
