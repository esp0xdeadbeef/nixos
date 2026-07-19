# Explicit DNS service endpoint material for the current CPM schema.
#
# The target contract is address-free. The pinned compiler cannot consume that
# service-origin contract without changing unrelated IPv6 route materialization,
# so inventory temporarily needs explicit access forwarders and a core service
# endpoint. Centralize those values here until CPM can bind the service directly
# to the core port facing upstream-selector.
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
  };
}
