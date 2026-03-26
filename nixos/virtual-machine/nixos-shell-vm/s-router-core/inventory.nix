# ./inventory.nix
{
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
    };
  };

  realization = {
    nodes = {
      esp0xdeadbeef-site-a-s-router-core-wan = {
        host = "lab-host";
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
              bridge = "br-fabric";
            };
            interface = {
              name = "ens3";
            };
          };
        };
      };
    };
  };
}
