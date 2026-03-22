{
  schemaVersion = 1;

  deployment.hosts = {
    s-router-policy-only = {
      uplinks = {
        upstream-core = {
          parent = "eth0";
          bridge = "br-upstream";
          mode = "vlan";
          vlan = 5;
        };

        trunk = {
          parent = "eth0";
          bridge = "br-fabric";
          mode = "trunk";
        };
      };

      bridgeNetworks = {
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
  };

  realization.nodes = {
    s-router-policy-only = {
      host = "s-router-policy-only";
      platform = "nixos-container";

      ports = {
        transit-admin = {
          link = "p2p-s-router-access-admin-s-router-policy";
          attach = {
            kind = "bridge";
            bridge = "tr100";
          };
          interface.name = "transit-admin";
        };

        transit-mgmt = {
          link = "p2p-s-router-access-mgmt-s-router-policy";
          attach = {
            kind = "bridge";
            bridge = "tr101";
          };
          interface.name = "transit-mgmt";
        };

        transit-client = {
          link = "p2p-s-router-access-client-s-router-policy";
          attach = {
            kind = "bridge";
            bridge = "tr102";
          };
          interface.name = "transit-client";
        };

        upstream-selector = {
          link = "p2p-s-router-policy-s-router-upstream-selector";
          attach = {
            kind = "bridge";
            bridge = "tr201";
          };
          interface.name = "upstream";
        };
      };
    };

    s-router-upstream-selector = {
      host = "s-router-policy-only";
      platform = "linux";

      ports = {
        policy = {
          link = "p2p-s-router-policy-s-router-upstream-selector";
          attach = {
            kind = "bridge";
            bridge = "tr201";
          };
          interface.name = "policy";
        };

        core = {
          link = "p2p-s-router-core-wan-s-router-upstream-selector";
          attach = {
            kind = "bridge";
            bridge = "tr200";
          };
          interface.name = "core";
        };
      };
    };

    s-router-core-wan = {
      host = "s-router-core-wan";
      platform = "linux";

      ports = {
        upstream-selector = {
          link = "p2p-s-router-core-wan-s-router-upstream-selector";
          attach = {
            kind = "bridge";
            bridge = "tr200";
          };
          interface.name = "upstream";
        };
      };
    };

    s-router-access-admin = {
      host = "s-router-policy";
      platform = "linux";

      ports = {
        transit-policy = {
          link = "p2p-s-router-access-admin-s-router-policy";
          attach = {
            kind = "bridge";
            bridge = "tr100";
          };
          interface.name = "access-admin";
        };
      };
    };

    s-router-access-client = {
      host = "s-router-policy";
      platform = "linux";

      ports = {
        transit-policy = {
          link = "p2p-s-router-access-client-s-router-policy";
          attach = {
            kind = "bridge";
            bridge = "tr102";
          };
          interface.name = "access-client";
        };
      };
    };

    s-router-access-mgmt = {
      host = "s-router-policy";
      platform = "linux";

      ports = {
        transit-policy = {
          link = "p2p-s-router-access-mgmt-s-router-policy";
          attach = {
            kind = "bridge";
            bridge = "tr101";
          };
          interface.name = "access-mgmt";
        };
      };
    };
  };
}
