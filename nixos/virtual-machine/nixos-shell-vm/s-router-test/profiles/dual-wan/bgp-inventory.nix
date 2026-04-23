let
  publicDns4 = [
    "1.1.1.1"
    "9.9.9.9"
  ];

  publicDns6 = [
    "2606:4700:4700::1111"
    "2620:fe::fe"
  ];
in
{
  controlPlane = {
    sites = {
      esp0xdeadbeef = {
        "site-a" = {
          routing = {
            mode = "bgp";
            bgp = {
              asn = 65000;
              topology = "policy-rr";
            };
          };
        };
      };
    };
  };

  deployment = {
    hosts = {
      s-router-test = {
        uplinks = {
          management = {
            parent = "eth0";
            mode = "vlan";
            vlan = 2;
            bridge = "vlan2";

            ipv4 = {
              method = "dhcp";
              enable = true;
              dhcp = true;
            };

            ipv6 = {
              method = "none";
              enable = false;
              acceptRA = false;
              dhcp = false;
              dhcpv6PD = false;
            };
          };

          uplink-isp-a = {
            parent = "eth0";
            mode = "vlan";
            vlan = 4;
            bridge = "br-uplink0";
            upstream = "isp-a";

            ipv4 = {
              method = "dhcp";
              enable = true;
              dhcp = true;
            };

            ipv6 = {
              method = "slaac";
              enable = true;
              acceptRA = true;
              dhcp = false;
              dhcpv6PD = false;
            };
          };

          uplink-isp-b = {
            parent = "eth0";
            mode = "vlan";
            vlan = 5;
            bridge = "br-uplink1";
            upstream = "isp-b";

            ipv4 = {
              method = "dhcp";
              enable = true;
              dhcp = true;
            };

            ipv6 = {
              method = "slaac";
              enable = true;
              acceptRA = true;
              dhcp = false;
              dhcpv6PD = false;
            };
          };
        };

        bridgeNetworks = {
          br-site-a-core-isp-a-upstream = { };
          br-site-a-core-isp-b-upstream = { };

          br-site-a-policy-upstream-access-admin-isp-a = { };
          br-site-a-policy-upstream-access-admin-isp-b = { };
          br-site-a-policy-upstream-access-client-isp-a = { };
          br-site-a-policy-upstream-access-client-isp-b = { };
          br-site-a-policy-upstream-access-mgmt-isp-a = { };
          br-site-a-policy-upstream-access-mgmt-isp-b = { };

          br-site-a-downstream-policy-access-admin = { };
          br-site-a-downstream-policy-access-client = { };
          br-site-a-downstream-policy-access-mgmt = { };

          br-site-a-downstream-admin = { };
          br-site-a-downstream-client = { };
          br-site-a-downstream-mgmt = { };

          admin = { };
          client = { };
          mgmt = { };
        };
      };
    };
  };

  realization = {
    nodes = {
      esp0xdeadbeef-site-a-s-router-core-isp-a = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-core-isp-a";
        };

        containers.default.runtimeName = "s-router-core-isp-a";

        ports = {
          upstream-selector = {
            link = "p2p-s-router-core-isp-a-s-router-upstream-selector";
            adapterName = "p2p-s-router-core-isp-a-s-router-upstream-selector-upstream-selector";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-core-isp-a-upstream";
            };
            interface.name = "upstream";
          };

          isp-a = {
            uplink = "isp-a";
            external = true;
            attach = {
              kind = "bridge";
              bridge = "br-uplink0";
            };
            interface.name = "isp-a";
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-core-isp-b = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-core-isp-b";
        };

        containers.default.runtimeName = "s-router-core-isp-b";

        ports = {
          upstream-selector = {
            link = "p2p-s-router-core-isp-b-s-router-upstream-selector";
            adapterName = "p2p-s-router-core-isp-b-s-router-upstream-selector-upstream-selector";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-core-isp-b-upstream";
            };
            interface.name = "upstream";
          };

          isp-b = {
            uplink = "isp-b";
            external = true;
            attach = {
              kind = "bridge";
              bridge = "br-uplink1";
            };
            interface.name = "isp-b";
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-access-admin = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-access-admin";
        };

        containers.default.runtimeName = "s-router-access-admin";
        services.dns = {
          listen = [
            "10.20.15.1"
            "fd42:dead:beef:15::1"
          ];
          allowFrom = [
            "10.20.15.0/24"
            "fd42:dead:beef:15::/64"
          ];
          forwarders = publicDns4 ++ publicDns6;
        };

        ports = {
          transit-downstream-selector = {
            link = "p2p-s-router-access-admin-s-router-downstream-selector";
            adapterName = "p2p-s-router-access-admin-s-router-downstream-selector-transit-downstream-selector";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-downstream-admin";
            };
            interface.name = "transit";
          };

          tenant-admin = {
            logicalInterface = "tenant-admin";
            attach = {
              kind = "bridge";
              bridge = "admin";
            };
            interface = {
              name = "tenant-admin";
              addr4 = "10.20.15.1/24";
              addr6 = "fd42:dead:beef:15::1/64";
            };
          };
        };

        advertisements = {
          dhcp4.tenant-admin = {
            interface = "tenant-admin";
            id = "admin";
            subnet = "10.20.15.0/24";
            pool = {
              start = "10.20.15.100";
              end = "10.20.15.200";
            };
            router = "10.20.15.1";
            dnsServers = publicDns4;
            domain = "lan.";
          };

          ipv6Ra.tenant-admin = {
            interface = "tenant-admin";
            prefixes = [ "fd42:dead:beef:15::/64" ];
            rdnss = publicDns6;
            dnssl = [ "lan." ];
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-access-client = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-access-client";
        };

        containers.default.runtimeName = "s-router-access-client";
        services.dns = {
          listen = [
            "10.20.20.1"
            "fd42:dead:beef:20::1"
          ];
          allowFrom = [
            "10.20.20.0/24"
            "fd42:dead:beef:20::/64"
          ];
          forwarders = publicDns4 ++ publicDns6;
        };

        ports = {
          transit-downstream-selector = {
            link = "p2p-s-router-access-client-s-router-downstream-selector";
            adapterName = "p2p-s-router-access-client-s-router-downstream-selector-transit-downstream-selector";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-downstream-client";
            };
            interface.name = "transit";
          };

          tenant-client = {
            logicalInterface = "tenant-client";
            attach = {
              kind = "bridge";
              bridge = "client";
            };
            interface = {
              name = "tenant-client";
              addr4 = "10.20.20.1/24";
              addr6 = "fd42:dead:beef:20::1/64";
            };
          };
        };

        advertisements = {
          dhcp4.tenant-client = {
            interface = "tenant-client";
            id = "client";
            subnet = "10.20.20.0/24";
            pool = {
              start = "10.20.20.100";
              end = "10.20.20.200";
            };
            router = "10.20.20.1";
            dnsServers = publicDns4;
            domain = "lan.";
          };

          ipv6Ra.tenant-client = {
            interface = "tenant-client";
            prefixes = [ "fd42:dead:beef:20::/64" ];
            rdnss = publicDns6;
            dnssl = [ "lan." ];
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-access-mgmt = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-access-mgmt";
        };

        containers.default.runtimeName = "s-router-access-mgmt";
        services.dns = {
          listen = [
            "10.20.10.1"
            "fd42:dead:beef:10::1"
          ];
          allowFrom = [
            "10.20.10.0/24"
            "fd42:dead:beef:10::/64"
          ];
          forwarders = publicDns4 ++ publicDns6;
        };

        ports = {
          transit-downstream-selector = {
            link = "p2p-s-router-access-mgmt-s-router-downstream-selector";
            adapterName = "p2p-s-router-access-mgmt-s-router-downstream-selector-transit-downstream-selector";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-downstream-mgmt";
            };
            interface.name = "transit";
          };

          tenant-mgmt = {
            logicalInterface = "tenant-mgmt";
            attach = {
              kind = "bridge";
              bridge = "mgmt";
            };
            interface = {
              name = "tenant-mgmt";
              addr4 = "10.20.10.1/24";
              addr6 = "fd42:dead:beef:10::1/64";
            };
          };
        };

        advertisements = {
          dhcp4.tenant-mgmt = {
            interface = "tenant-mgmt";
            id = "mgmt";
            subnet = "10.20.10.0/24";
            pool = {
              start = "10.20.10.100";
              end = "10.20.10.200";
            };
            router = "10.20.10.1";
            dnsServers = publicDns4;
            domain = "lan.";
          };

          ipv6Ra.tenant-mgmt = {
            interface = "tenant-mgmt";
            prefixes = [ "fd42:dead:beef:10::/64" ];
            rdnss = publicDns6;
            dnssl = [ "lan." ];
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-downstream-selector = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-downstream-selector";
        };

        containers.default.runtimeName = "s-router-downstream-selector";

        ports = {
          policy-admin = {
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-admin";
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-admin-policy-admin";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-downstream-policy-access-admin";
            };
            interface.name = "policy-admin";
          };

          policy-client = {
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client";
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client-policy-client";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-downstream-policy-access-client";
            };
            interface.name = "policy-client";
          };

          policy-mgmt = {
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-mgmt";
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-mgmt-policy-mgmt";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-downstream-policy-access-mgmt";
            };
            interface.name = "policy-mgmt";
          };

          access-admin = {
            link = "p2p-s-router-access-admin-s-router-downstream-selector";
            adapterName = "p2p-s-router-access-admin-s-router-downstream-selector-access-admin";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-downstream-admin";
            };
            interface.name = "access-admin";
          };

          access-client = {
            link = "p2p-s-router-access-client-s-router-downstream-selector";
            adapterName = "p2p-s-router-access-client-s-router-downstream-selector-access-client";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-downstream-client";
            };
            interface.name = "access-client";
          };

          access-mgmt = {
            link = "p2p-s-router-access-mgmt-s-router-downstream-selector";
            adapterName = "p2p-s-router-access-mgmt-s-router-downstream-selector-access-mgmt";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-downstream-mgmt";
            };
            interface.name = "access-mgmt";
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-policy = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-policy-only";
        };

        containers.default.runtimeName = "s-router-policy-only";

        ports = {
          upstream-admin-isp-a = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-a";
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-a-upstream-admin-isp-a";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-policy-upstream-access-admin-isp-a";
            };
            interface.name = "up-admin-a";
          };

          upstream-admin-isp-b = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-b";
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-b-upstream-admin-isp-b";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-policy-upstream-access-admin-isp-b";
            };
            interface.name = "up-admin-b";
          };

          upstream-client-isp-a = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-a";
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-a-upstream-client-isp-a";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-policy-upstream-access-client-isp-a";
            };
            interface.name = "up-client-a";
          };

          upstream-client-isp-b = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-b";
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-b-upstream-client-isp-b";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-policy-upstream-access-client-isp-b";
            };
            interface.name = "up-client-b";
          };

          upstream-mgmt-isp-a = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-a";
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-a-upstream-mgmt-isp-a";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-policy-upstream-access-mgmt-isp-a";
            };
            interface.name = "up-mgmt-a";
          };

          upstream-mgmt-isp-b = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-b";
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-b-upstream-mgmt-isp-b";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-policy-upstream-access-mgmt-isp-b";
            };
            interface.name = "up-mgmt-b";
          };

          downstream-admin = {
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-admin";
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-admin-downstream-admin";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-downstream-policy-access-admin";
            };
            interface.name = "downstream-admin";
          };

          downstream-client = {
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client";
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client-downstream-client";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-downstream-policy-access-client";
            };
            interface.name = "downstream-client";
          };

          downstream-mgmt = {
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-mgmt";
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-mgmt-downstream-mgmt";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-downstream-policy-access-mgmt";
            };
            interface.name = "downstream-mgmt";
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-upstream-selector = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-upstream-selector";
        };

        containers.default.runtimeName = "s-router-upstream-selector";

        ports = {
          core-isp-a = {
            link = "p2p-s-router-core-isp-a-s-router-upstream-selector";
            adapterName = "p2p-s-router-core-isp-a-s-router-upstream-selector-core-isp-a";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-core-isp-a-upstream";
            };
            interface.name = "core-a";
          };

          core-isp-b = {
            link = "p2p-s-router-core-isp-b-s-router-upstream-selector";
            adapterName = "p2p-s-router-core-isp-b-s-router-upstream-selector-core-isp-b";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-core-isp-b-upstream";
            };
            interface.name = "core-b";
          };

          policy-admin-isp-a = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-a";
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-a-policy-admin-isp-a";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-policy-upstream-access-admin-isp-a";
            };
            interface.name = "pol-admin-a";
          };

          policy-admin-isp-b = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-b";
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-b-policy-admin-isp-b";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-policy-upstream-access-admin-isp-b";
            };
            interface.name = "pol-admin-b";
          };

          policy-client-isp-a = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-a";
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-a-policy-client-isp-a";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-policy-upstream-access-client-isp-a";
            };
            interface.name = "pol-client-a";
          };

          policy-client-isp-b = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-b";
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-b-policy-client-isp-b";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-policy-upstream-access-client-isp-b";
            };
            interface.name = "pol-client-b";
          };

          policy-mgmt-isp-a = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-a";
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-a-policy-mgmt-isp-a";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-policy-upstream-access-mgmt-isp-a";
            };
            interface.name = "pol-mgmt-a";
          };

          policy-mgmt-isp-b = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-b";
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-b-policy-mgmt-isp-b";
            attach = {
              kind = "bridge";
              bridge = "br-site-a-policy-upstream-access-mgmt-isp-b";
            };
            interface.name = "pol-mgmt-b";
          };
        };
      };
    };
  };
}
