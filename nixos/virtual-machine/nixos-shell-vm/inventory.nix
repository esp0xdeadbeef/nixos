{
  schemaVersion = 1;

  deployment = {
    hosts = {
      s-router-access = {
        uplinks = {
          management = {
            parent = "eth0";
            mode = "vlan";
            vlan = 2;
            bridge = "vlan2";
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

          br-fabric = {
            ConfigureWithoutCarrier = true;
          };
        };

        transitBridges = {
          tr100 = {
            name = "tr100";
            vlan = 100;
            parentUplink = "trunk";
          };

          tr101 = {
            name = "tr101";
            vlan = 101;
            parentUplink = "trunk";
          };

          tr102 = {
            name = "tr102";
            vlan = 102;
            parentUplink = "trunk";
          };

          admin = {
            name = "admin";
            vlan = 10;
            parentUplink = "trunk";
          };

          client = {
            name = "client";
            vlan = 20;
            parentUplink = "trunk";
          };

          mgmt = {
            name = "mgmt";
            vlan = 30;
            parentUplink = "trunk";
          };
        };
      };

      s-router-core = {
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

            ipv4 = {
              method = "dhcp";
            };

            ipv6 = {
              method = "slaac";
            };
          };

          fabric = {
            parent = "eth0";
            mode = "vlan";
            vlan = 200;
            bridge = "br-fabric";
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
      };

      s-router-policy = {
        uplinks = {
          management = {
            parent = "eth0";
            mode = "vlan";
            vlan = 2;
            bridge = "vlan2";
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

          br-fabric = {
            ConfigureWithoutCarrier = true;
          };
        };

        transitBridges = {
          tr100 = {
            name = "tr100";
            vlan = 100;
            parentUplink = "trunk";
          };

          tr101 = {
            name = "tr101";
            vlan = 101;
            parentUplink = "trunk";
          };

          tr102 = {
            name = "tr102";
            vlan = 102;
            parentUplink = "trunk";
          };

          tr200 = {
            name = "tr200";
            vlan = 200;
            parentUplink = "trunk";
          };

          tr201 = {
            name = "tr201";
            vlan = 201;
            parentUplink = "trunk";
          };

          tr202 = {
            name = "tr202";
            vlan = 202;
            parentUplink = "trunk";
          };
        };
      };
    };
  };

  realization = {
    nodes = {
      esp0xdeadbeef-site-a-s-router-core-wan = {
        host = "s-router-core";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-core-wan";
          site = "site-a";
        };

        ports = {
          upstream-selector = {
            link = "p2p-s-router-core-wan-s-router-upstream-selector";
            attach = {
              kind = "bridge";
              bridge = "br-fabric";
            };
            interface = {
              name = "ens3";
            };
          };

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
        };
      };

      s-router-access-admin = {
        host = "s-router-access";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-admin";
          site = "site-a";
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
      };

      s-router-access-client = {
        host = "s-router-access";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-client";
          site = "site-a";
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
      };

      s-router-access-mgmt = {
        host = "s-router-access";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-mgmt";
          site = "site-a";
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
      };

      s-router-policy-only = {
        host = "s-router-policy";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-policy";
          site = "site-a";
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
              bridge = "tr202";
            };
            interface = {
              name = "downstream";
            };
          };
        };
      };

      s-router-upstream-selector = {
        host = "s-router-policy";
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

      s-router-downstream-selector = {
        host = "s-router-policy";
        platform = "linux";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-downstream-selector";
          site = "site-a";
        };

        ports = {
          policy = {
            link = "p2p-s-router-downstream-selector-s-router-policy";
            attach = {
              kind = "bridge";
              bridge = "tr202";
            };
            interface = {
              name = "policy"
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
    };
  };

  render = {
    hosts = {
      s-router-access = {
        deploymentHost = "s-router-access";
      };

      s-router-core = {
        containerTemplate = "wan";
        deploymentHost = "s-router-core";
        runtimeRole = "core";
        wanUplink = "upstream-core";
      };

      s-router-core-wan = {
        deploymentHost = "s-router-core";
      };

      s-router-policy-only = {
        containerName = "s-router-policy-only-container";
        deploymentHost = "s-router-policy";
      };

      s-router-upstream-selector = {
        deploymentHost = "s-router-policy";
      };

      s-router-downstream-selector = {
        deploymentHost = "s-router-policy";
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
