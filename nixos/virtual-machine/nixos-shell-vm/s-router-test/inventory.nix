{
  schemaVersion = 1;

  endpoints = {
    web01 = {
      ipv4 = [ "10.20.15.10" ];
      ipv6 = [ "fd42:dead:beef:15::10" ];
    };

    s-sigma = {
      ipv4 = [ "10.20.10.10" ];
      ipv6 = [ "fd42:dead:beef:10::10" ];
    };
  };

  deployment = {
    hosts = {
      s-router-test = {
        wanUplink = "upstream-core";

        uplinks = {
          management = {
            parent = "eth0";
            mode = "vlan";
            vlan = 2;
            bridge = "vlan2";
          };

          upstream-core = {
            parent = "eth0";
            mode = "vlan";
            vlan = 5;
            bridge = "br-upstream";

            ipv6 = {
              method = "slaac";
              enable = true;
              acceptRA = true;
              dhcp = false;
              dhcpv6PD = false;
            };

            ipv4 = {
              method = "dhcp";
              enable = true;
              dhcp = true;
            };
          };

          trunk = {
            parent = "eth0";
            bridge = "br-fabric";
            mode = "trunk";
          };
        };

        bridgeNetworks = {
          vlan2 = {
            DHCP = "ipv4";
            IPv6AcceptRA = false;
            LinkLocalAddressing = "ipv4";
            ConfigureWithoutCarrier = true;
          };

          br-upstream = {
            ConfigureWithoutCarrier = true;
          };

          br-fabric = {
            ConfigureWithoutCarrier = true;
          };
        };

        transitBridges = {
          tr100 = {
            name = "tr100";
            vlan = 400;
            parentUplink = "trunk";
          };

          tr101 = {
            name = "tr101";
            vlan = 401;
            parentUplink = "trunk";
          };

          tr102 = {
            name = "tr102";
            vlan = 402;
            parentUplink = "trunk";
          };

          tr103 = {
            name = "tr103";
            vlan = 403;
            parentUplink = "trunk";
          };

          tr200 = {
            name = "tr200";
            vlan = 500;
            parentUplink = "trunk";
          };

          tr201 = {
            name = "tr201";
            vlan = 501;
            parentUplink = "trunk";
          };

          admin = {
            name = "admin";
            vlan = 310;
            parentUplink = "trunk";
          };

          client = {
            name = "client";
            vlan = 320;
            parentUplink = "trunk";
          };

          mgmt = {
            name = "mgmt";
            vlan = 330;
            parentUplink = "trunk";
          };
        };
      };
    };
  };

  realization = {
    nodes = {
      esp0xdeadbeef-site-a-s-router-core-wan = {
        host = "s-router-test";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-core-wan";
        };

        ports = {
          upstream-selector = {
            link = "p2p-s-router-core-wan-s-router-upstream-selector";
            attach = {
              kind = "bridge";
              bridge = "tr200";
            };
            interface = {
              name = "ens3";
            };
          };

          wan = {
            upstream = "upstream-core";
            link = "wan";
            attach = {
              kind = "bridge";
              bridge = "br-upstream";
            };
            interface = {
              name = "wan";
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-access-admin = {
        host = "s-router-test";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-access-admin";
        };

        ports = {
          transit-downstream-selector = {
            link = "p2p-s-router-access-admin-s-router-downstream-selector";
            attach = {
              kind = "bridge";
              bridge = "tr100";
            };
            interface = {
              name = "access-admin";
            };
          };

          tenant-admin = {
            logicalInterface = "tenant-admin";
            attach = {
              kind = "bridge";
              bridge = "admin";
            };
            interface = {
              name = "tenant-admin";
            };
          };
        };

        advertisements = {
          dhcp4 = {
            tenant-admin = {
              interface = "tenant-admin";
              id = "tenant-admin";
              subnet = "10.20.15.0/24";
              pool = {
                start = "10.20.15.100";
                end = "10.20.15.200";
              };
              router = "10.20.15.1";
              dnsServers = [ "10.20.15.1" ];
              domain = "lan.";
            };
          };

          ipv6Ra = {
            tenant-admin = {
              interface = "tenant-admin";
              prefixes = [ "fd42:dead:beef:15::/64" ];
              rdnss = [ "fd42:dead:beef:15::1" ];
              dnssl = [ "lan." ];
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-access-client = {
        host = "s-router-test";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-access-client";
        };

        ports = {
          transit-downstream-selector = {
            link = "p2p-s-router-access-client-s-router-downstream-selector";
            attach = {
              kind = "bridge";
              bridge = "tr102";
            };
            interface = {
              name = "access-client";
            };
          };

          tenant-client = {
            logicalInterface = "tenant-client";
            attach = {
              kind = "bridge";
              bridge = "client";
            };
            interface = {
              name = "tenant-client";
            };
          };
        };

        advertisements = {
          dhcp4 = {
            tenant-client = {
              interface = "tenant-client";
              id = "tenant-client";
              subnet = "10.20.20.0/24";
              pool = {
                start = "10.20.20.100";
                end = "10.20.20.200";
              };
              router = "10.20.20.1";
              dnsServers = [ "10.20.20.1" ];
              domain = "lan.";
            };
          };

          ipv6Ra = {
            tenant-client = {
              interface = "tenant-client";
              prefixes = [ "fd42:dead:beef:20::/64" ];
              rdnss = [ "fd42:dead:beef:20::1" ];
              dnssl = [ "lan." ];
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-access-mgmt = {
        host = "s-router-test";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-access-mgmt";
        };

        ports = {
          transit-downstream-selector = {
            link = "p2p-s-router-access-mgmt-s-router-downstream-selector";
            attach = {
              kind = "bridge";
              bridge = "tr101";
            };
            interface = {
              name = "access-mgmt";
            };
          };

          tenant-mgmt = {
            logicalInterface = "tenant-mgmt";
            attach = {
              kind = "bridge";
              bridge = "mgmt";
            };
            interface = {
              name = "tenant-mgmt";
            };
          };
        };

        advertisements = {
          dhcp4 = {
            tenant-mgmt = {
              interface = "tenant-mgmt";
              id = "tenant-mgmt";
              subnet = "10.20.10.0/24";
              pool = {
                start = "10.20.10.100";
                end = "10.20.10.200";
              };
              router = "10.20.10.1";
              dnsServers = [ "10.20.10.1" ];
              domain = "lan.";
            };
          };

          ipv6Ra = {
            tenant-mgmt = {
              interface = "tenant-mgmt";
              prefixes = [ "fd42:dead:beef:10::/64" ];
              rdnss = [ "fd42:dead:beef:10::1" ];
              dnssl = [ "lan." ];
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-downstream-selector = {
        host = "s-router-test";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-downstream-selector";
        };

        ports = {
          policy = {
            link = "p2p-s-router-downstream-selector-s-router-policy";
            attach = {
              kind = "bridge";
              bridge = "tr103";
            };
            interface = {
              name = "policy";
            };
          };

          access-admin = {
            link = "p2p-s-router-access-admin-s-router-downstream-selector";
            attach = {
              kind = "bridge";
              bridge = "tr100";
            };
            interface = {
              name = "access-admin";
            };
          };

          access-client = {
            link = "p2p-s-router-access-client-s-router-downstream-selector";
            attach = {
              kind = "bridge";
              bridge = "tr102";
            };
            interface = {
              name = "access-client";
            };
          };

          access-mgmt = {
            link = "p2p-s-router-access-mgmt-s-router-downstream-selector";
            attach = {
              kind = "bridge";
              bridge = "tr101";
            };
            interface = {
              name = "access-mgmt";
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-policy = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-policy";
        };

        ports = {
          upstream-selector = {
            link = "p2p-s-router-policy-s-router-upstream-selector";
            attach = {
              kind = "bridge";
              bridge = "tr201";
            };
            interface = {
              name = "upstream";
            };
          };

          downstream-selector = {
            link = "p2p-s-router-downstream-selector-s-router-policy";
            attach = {
              kind = "bridge";
              bridge = "tr103";
            };
            interface = {
              name = "downstream";
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-upstream-selector = {
        host = "s-router-test";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-upstream-selector";
        };

        ports = {
          core = {
            link = "p2p-s-router-core-wan-s-router-upstream-selector";
            attach = {
              kind = "bridge";
              bridge = "tr200";
            };
            interface = {
              name = "core";
            };
          };

          policy = {
            link = "p2p-s-router-policy-s-router-upstream-selector";
            attach = {
              kind = "bridge";
              bridge = "tr201";
            };
            interface = {
              name = "policy";
            };
          };
        };
      };
    };
  };

  render = {
    hosts = {
      s-router-access = {
        deploymentHost = "s-router-test";
      };

      s-router-core = {
        containerTemplate = "wan";
        deploymentHost = "s-router-test";
        runtimeRole = "core";
        wanUplink = "upstream-core";
      };

      s-router-core-wan = {
        deploymentHost = "s-router-test";
      };

      s-router-downstream-selector = {
        deploymentHost = "s-router-test";
      };

      s-router-policy = {
        deploymentHost = "s-router-test";
      };

      s-router-upstream-selector = {
        deploymentHost = "s-router-test";
      };
    };
  };

  secrets = {
    pppoe-password = {
      owner = "root";
      mode = "0400";
    };

    pppoe-username = {
      owner = "root";
      mode = "0400";
    };

    subnet-ipv6 = {
      owner = "root";
      mode = "0400";
    };
  };
}
