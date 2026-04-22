{
  esp0xdeadbeef.site-a = {
    pools = {
      p2p = {
        ipv4 = "10.10.0.0/24";
        ipv6 = "fd42:dead:beef:1000::/118";
      };

      loopback = {
        ipv4 = "10.19.0.0/24";
        ipv6 = "fd42:dead:beef:1900::/118";
      };
    };

    ownership = {
      prefixes = [
        {
          kind = "tenant";
          name = "mgmt";
          ipv4 = "10.20.10.0/24";
          ipv6 = "fd42:dead:beef:10::/64";
        }
        {
          kind = "tenant";
          name = "admin";
          ipv4 = "10.20.15.0/24";
          ipv6 = "fd42:dead:beef:15::/64";
        }
        {
          kind = "tenant";
          name = "client";
          ipv4 = "10.20.20.0/24";
          ipv6 = "fd42:dead:beef:20::/64";
        }
        {
          kind = "tenant";
          name = "dmz";
          ipv4 = "10.20.30.0/24";
          ipv6 = "fd42:dead:beef:30::/64";
        }
      ];

      endpoints = [
        {
          kind = "host";
          name = "s-sigma";
          tenant = "mgmt";
        }
        {
          kind = "host";
          name = "nebula01";
          tenant = "dmz";
        }
        {
          kind = "host";
          name = "wireguard01";
          tenant = "dmz";
        }
        {
          kind = "host";
          name = "dmzweb01";
          tenant = "dmz";
        }
      ];
    };

    communicationContract = {
      trafficTypes = [
        {
          name = "icmp";
          match = [
            {
              proto = "icmp";
              family = "any";
            }
          ];
        }

        {
          name = "dns";
          match = [
            {
              proto = "udp";
              dports = [ 53 ];
              family = "any";
            }
            {
              proto = "tcp";
              dports = [ 53 ];
              family = "any";
            }
          ];
        }

        {
          name = "ssh";
          match = [
            {
              proto = "tcp";
              dports = [ 22 ];
              family = "any";
            }
          ];
        }

        {
          name = "web-ui";
          match = [
            {
              proto = "tcp";
              dports = [ 8080 ];
              family = "any";
            }
          ];
        }

        {
          name = "nebula";
          match = [
            {
              proto = "tcp";
              dports = [ 4242 ];
              family = "any";
            }
            {
              proto = "udp";
              dports = [ 4242 ];
              family = "any";
            }
          ];
        }

        {
          name = "wireguard";
          match = [
            {
              proto = "udp";
              dports = [ 51820 ];
              family = "any";
            }
          ];
        }
      ];

      services = [
        {
          name = "site-dns";
          trafficType = "dns";
          providers = [ "s-sigma" ];
        }

        {
          name = "jump-host";
          trafficType = "ssh";
          providers = [ "s-sigma" ];
        }

        {
          name = "dmz-nebula";
          trafficType = "nebula";
          providers = [ "nebula01" ];
        }

        {
          name = "dmz-wireguard";
          trafficType = "wireguard";
          providers = [ "wireguard01" ];
        }

        {
          name = "dmz-web";
          trafficType = "web-ui";
          providers = [ "dmzweb01" ];
        }
      ];

      relations = [
        {
          id = "allow-mgmt-internal";
          priority = 10;
          from = {
            kind = "tenant-set";
            members = [ "mgmt" ];
          };
          to = {
            kind = "tenant-set";
            members = [
              "mgmt"
              "admin"
              "client"
              "dmz"
            ];
          };
          trafficType = "any";
          action = "allow";
        }

        {
          id = "allow-icmp-anywhere";
          priority = 20;
          from = {
            kind = "tenant-set";
            members = [
              "mgmt"
              "admin"
              "client"
              "dmz"
            ];
          };
          to = "any";
          trafficType = "icmp";
          action = "allow";
        }

        {
          id = "allow-tenants-to-wan";
          priority = 100;
          from = {
            kind = "tenant-set";
            members = [
              "mgmt"
              "admin"
              "client"
              "dmz"
            ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
          action = "allow";
        }

        {
          id = "allow-wan-to-jump-host";
          priority = 110;
          from = {
            kind = "external";
            name = "wan";
          };
          to = {
            kind = "service";
            name = "jump-host";
          };
          trafficType = "ssh";
          action = "allow";
        }

        {
          id = "allow-wan-to-mgmt-icmp";
          priority = 115;
          from = {
            kind = "external";
            name = "wan";
          };
          to = {
            kind = "tenant";
            name = "mgmt";
          };
          trafficType = "icmp";
          action = "allow";
        }

        {
          id = "allow-wan-to-dmz-nebula";
          priority = 120;
          from = {
            kind = "external";
            name = "wan";
          };
          to = {
            kind = "service";
            name = "dmz-nebula";
          };
          trafficType = "nebula";
          action = "allow";
        }

        {
          id = "allow-wan-to-dmz-wireguard";
          priority = 121;
          from = {
            kind = "external";
            name = "wan";
          };
          to = {
            kind = "service";
            name = "dmz-wireguard";
          };
          trafficType = "wireguard";
          action = "allow";
        }

        {
          id = "allow-wan-to-dmz-web";
          priority = 122;
          from = {
            kind = "external";
            name = "wan";
          };
          to = {
            kind = "service";
            name = "dmz-web";
          };
          trafficType = "web-ui";
          action = "allow";
        }
      ];

      interfaceTags = {
        tenant-mgmt = "mgmt";
        tenant-admin = "admin";
        tenant-client = "client";
        tenant-dmz = "dmz";
        external-wan = "wan";
        service-site-dns = "site-dns";
        service-jump-host = "jump-host";
        service-dmz-nebula = "dmz-nebula";
        service-dmz-wireguard = "dmz-wireguard";
        service-dmz-web = "dmz-web";
      };
    };

    topology = {
      nodes = {
        s-router-core-wan = {
          role = "core";

          uplinks = {
            wan = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
            };
          };
        };

        s-router-upstream-selector = {
          role = "upstream-selector";
        };

        s-router-policy-only = {
          role = "policy";
        };

        s-router-downstream-selector = {
          role = "downstream-selector";
        };

        s-router-access-mgmt = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "mgmt";
            }
          ];
        };

        s-router-access-admin = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "admin";
            }
          ];
        };

        s-router-access-client = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "client";
            }
          ];
        };

        s-router-access-dmz = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "dmz";
            }
          ];
        };
      };

      links = [
        [
          "s-router-core-wan"
          "s-router-upstream-selector"
        ]
        [
          "s-router-upstream-selector"
          "s-router-policy-only"
        ]
        [
          "s-router-policy-only"
          "s-router-downstream-selector"
        ]
        [
          "s-router-downstream-selector"
          "s-router-access-client"
        ]
        [
          "s-router-downstream-selector"
          "s-router-access-admin"
        ]
        [
          "s-router-downstream-selector"
          "s-router-access-mgmt"
        ]
        [
          "s-router-downstream-selector"
          "s-router-access-dmz"
        ]
      ];
    };
  };
}
