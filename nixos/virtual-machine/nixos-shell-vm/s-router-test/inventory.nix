{
  schemaVersion = 1;

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
          name = "s-router-core-wan";
          site = "site-a";
        };

        ports = {
          wan = {
            uplink = "wan";
            attach = {
              kind = "bridge";
              bridge = "br-upstream";
            };
            interface = {
              name = "wan";
            };
          };

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
        };
      };

      s-router-access-admin = {
        host = "s-router-test";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-admin";
          site = "site-a";
        };

        ports = {
          transit-policy = {
            link = "p2p-s-router-access-admin-s-router-policy";
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
      };

      s-router-access-client = {
        host = "s-router-test";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-client";
          site = "site-a";
        };

        ports = {
          transit-policy = {
            link = "p2p-s-router-access-client-s-router-policy";
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
      };

      s-router-access-mgmt = {
        host = "s-router-test";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-mgmt";
          site = "site-a";
        };

        ports = {
          transit-policy = {
            link = "p2p-s-router-access-mgmt-s-router-policy";
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
      };

      s-router-policy-only = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-policy";
          site = "site-a";
        };

        ports = {
          transit-admin = {
            link = "p2p-s-router-access-admin-s-router-policy";
            attach = {
              kind = "bridge";
              bridge = "tr100";
            };
            interface = {
              name = "transit-admin";
            };
          };

          transit-client = {
            link = "p2p-s-router-access-client-s-router-policy";
            attach = {
              kind = "bridge";
              bridge = "tr102";
            };
            interface = {
              name = "transit-client";
            };
          };

          transit-mgmt = {
            link = "p2p-s-router-access-mgmt-s-router-policy";
            attach = {
              kind = "bridge";
              bridge = "tr101";
            };
            interface = {
              name = "transit-mgmt";
            };
          };

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
        };
      };

      s-router-upstream-selector = {
        host = "s-router-test";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-upstream-selector";
          site = "site-a";
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

      s-router-policy-only = {
        containerName = "s-router-policy-only-container";
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
