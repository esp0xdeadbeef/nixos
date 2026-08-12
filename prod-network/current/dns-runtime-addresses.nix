# DNS runtime addresses extended from the production set with the IOT
# (VLAN 8) access entry. Keep the production values as the primary
# reference; any change here must also be reflected in ../current/.
{
  resolver = {
    node = "core";
    service = "core-dns";
    ipv4 = "10.10.0.6";
    ipv6 = "fd42:dead:beef:1000::6";
  };

  requesters = {
    access-vlan2 = {
      ipv4 = "192.168.1.1";
      ipv6 = "fd42:1::1";
      clientIpv4 = "192.168.1.0/24";
      clientIpv6 = "fd42:1::/64";
    };

    access-vlan3 = {
      ipv4 = "192.168.3.1";
      ipv6 = "fd42:dead:beef:3::1";
      clientIpv4 = "192.168.3.0/24";
      clientIpv6 = "fd42:dead:beef:3::/64";
    };

    access-vlan7 = {
      ipv4 = "192.168.2.1";
      ipv6 = "fd42:dead:beef:7::1";
      clientIpv4 = "192.168.2.0/24";
      clientIpv6 = "fd42:dead:beef:7::/64";
    };

    access-vlan8 = {
      ipv4 = "192.168.8.1";
      ipv6 = "fd42:dead:beef:8::1";
      clientIpv4 = "192.168.8.0/24";
      clientIpv6 = "fd42:dead:beef:8::/64";
    };
  };
}
