{
  policyAccessTransitBase = 100;

  deployment.host.s-router-access = {
    uplink = {
      parent = "eth0";
      management = {
        vlan = 2;
        bridge = "vlan2";
        addressing = {
          ipv4.mode = "dhcp";
          ipv6.mode = "disabled";
        };
      };
    };
  };

  fabric = {
    s-router-access-admin = {
      platform = "linux";
      ports = {
        port1 = {
          link = "p2p-s-router-access-admin-s-router-policy";
          vlan = 100;
        };
        port2 = {
          attachment = {
            kind = "tenant";
            name = "admin";
          };
        };
      };
    };

    s-router-access-mgmt = {
      platform = "linux";
      ports = {
        port1 = {
          link = "p2p-s-router-access-mgmt-s-router-policy";
          vlan = 101;
        };
        port2 = {
          attachment = {
            kind = "tenant";
            name = "mgmt";
          };
        };
      };
    };

    s-router-access-client = {
      platform = "linux";
      ports = {
        port1 = {
          link = "p2p-s-router-access-client-s-router-policy";
          vlan = 102;
        };
        port2 = {
          attachment = {
            kind = "tenant";
            name = "client";
          };
        };
      };
    };
  };
}
