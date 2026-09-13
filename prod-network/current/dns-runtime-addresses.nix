# Neon-site DNS runtime addresses for the independent testing model.
#
# prod-network/testing is self-contained and does not mirror
# prod-network/current; this file is the authoritative neon DNS runtime
# address set for the testing model.
{
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
    access-mgmt = {
      ipv4 = "10.3.10.1";
      ipv6 = "fd42:dead:beef:310::1";
      clientIpv4 = "10.3.10.0/24";
      clientIpv6 = "fd42:dead:beef:310::/64";
    };

    access-svc = {
      ipv4 = "10.3.20.1";
      ipv6 = "fd42:dead:beef:320::1";
      clientIpv4 = "10.3.20.0/24";
      clientIpv6 = "fd42:dead:beef:320::/64";
    };

    access-clients = {
      ipv4 = "10.3.30.1";
      ipv6 = "fd42:dead:beef:330::1";
      clientIpv4 = "10.3.30.0/24";
      clientIpv6 = "fd42:dead:beef:330::/64";
    };

    access-iot = {
      ipv4 = "10.3.50.1";
      ipv6 = "fd42:dead:beef:350::1";
      clientIpv4 = "10.3.50.0/24";
      clientIpv6 = "fd42:dead:beef:350::/64";
    };

    access-iot-srv = {
      ipv4 = "10.3.51.1";
      ipv6 = "fd42:dead:beef:351::1";
      clientIpv4 = "10.3.51.0/24";
      clientIpv6 = "fd42:dead:beef:351::/64";
    };

    access-dmz = {
      ipv4 = "10.3.60.1";
      ipv6 = "fd42:dead:beef:360::1";
      clientIpv4 = "10.3.60.0/24";
      clientIpv6 = "fd42:dead:beef:360::/64";
    };

    access-unlock = {
      ipv4 = "10.3.90.1";
      ipv6 = "fd42:dead:beef:390::1";
      clientIpv4 = "10.3.90.0/24";
      clientIpv6 = "fd42:dead:beef:390::/64";
    };
  };
}
