{
  schemaVersion = 1;

  deployment = {
    hosts = {
      lab-host = {
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
              enable = true;

              # IPv6 Router Advertisements / SLAAC on the WAN interface.
              acceptRA = true;

              # Set to true if the ISP uses stateful DHCPv6 on the WAN link.
              dhcp = false;

              # Set to true if you want DHCPv6 Prefix Delegation.
              dhcpv6PD = false;
            };

            # Uncomment and fill these only when using PPPoE.
            # pppoe = {
            #   enable = true;
            #   usernameSecret = "pppoe-username";
            #   passwordSecret = "pppoe-password";
            #   mtu = 1492;
            #   mru = 1492;
            # };
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

      s-router-core-wan = {
        uplinks = {
          trunk = {
            parent = "eth0";
            bridge = "br-fabric";
            mode = "trunk";
          };
        };

        transitBridges = {
          tr200 = {
            name = "tr200";
            vlan = 200;
            parentUplink = "trunk";
          };
        };
      };

      s-router-policy = {
        uplinks = {
          trunk = {
            parent = "eth0";
            bridge = "br-fabric";
            mode = "trunk";
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

          tr201 = {
            name = "tr201";
            vlan = 201;
            parentUplink = "trunk";
          };
        };
      };

      s-router-policy-only = {
        uplinks = {
          management = {
            parent = "eth0";
            mode = "vlan";
            vlan = 2;
            bridge = "vlan2";
          };

          upstream-core = {
            parent = "eth0";
            bridge = "br-upstream";
            mode = "vlan";
            vlan = 5;

            ipv6 = {
              enable = true;

              # IPv6 Router Advertisements / SLAAC on the WAN interface.
              acceptRA = true;

              # Set to true if the ISP uses stateful DHCPv6 on the WAN link.
              dhcp = false;

              # Set to true if you want DHCPv6 Prefix Delegation.
              dhcpv6PD = false;
            };

            # Uncomment and fill these only when using PPPoE.
            # pppoe = {
            #   enable = true;
            #   usernameSecret = "pppoe-username";
            #   passwordSecret = "pppoe-password";
            #   mtu = 1492;
            #   mru = 1492;
            # };
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
        };
      };
    };
  };

  realization = {
    nodes = {
      esp0xdeadbeef-site-a-s-router-core-wan = {
        host = "lab-host";
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
        };
      };

      s-router-access-admin = {
        host = "s-router-policy";
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
        };
      };

      s-router-access-client = {
        host = "s-router-policy";
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
        };
      };

      s-router-access-mgmt = {
        host = "s-router-policy";
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
        };
      };

      s-router-policy-only = {
        host = "s-router-policy-only";
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
        host = "s-router-policy-only";
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
      s-router-core = {
        containerTemplate = "wan";
        deploymentHost = "lab-host";
        runtimeRole = "core";
        wanUplink = "upstream-core";
      };

      s-router-core-wan = {
        deploymentHost = "s-router-core-wan";
      };

      s-router-policy = {
        deploymentHost = "s-router-policy";
      };

      s-router-policy-only = {
        containerName = "s-router-policy-only-container";
        deploymentHost = "s-router-policy-only";
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
