let
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
      name = "web";
      match = [
        {
          proto = "tcp";
          dports = [
            80
            443
          ];
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

  allowTenantToWan =
    tenant: priority:
    {
      id = "allow-${tenant}-to-wan";
      inherit priority;
      from = {
        kind = "tenant";
        name = tenant;
      };
      to = {
        kind = "external";
        name = "wan";
      };
      trafficType = "any";
      action = "allow";
    };
in
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
          name = "vlan2";
          ipv4 = "192.168.1.0/24";
          ipv6 = "fd42:1::/64";
        }
        {
          kind = "tenant";
          name = "vlan7";
          ipv4 = "192.168.2.0/24";
          ipv6 = "fd42:dead:beef:7::/64";
        }
      ];

      endpoints = [
        {
          kind = "host";
          name = "vlan2-dns";
          tenant = "vlan2";
          ipv4 = [ "192.168.1.1" ];
          ipv6 = [ "fd42:1::1" ];
        }
        {
          kind = "host";
          name = "vlan7-dns";
          tenant = "vlan7";
          ipv4 = [ "192.168.2.1" ];
          ipv6 = [ "fd42:dead:beef:7::1" ];
        }
      ];
    };

    communicationContract = {
      inherit trafficTypes;
      services = [
        {
          name = "vlan2-dns";
          providers = [ "vlan2-dns" ];
          trafficType = "dns";
        }
        {
          name = "vlan7-dns";
          providers = [ "vlan7-dns" ];
          trafficType = "dns";
        }
      ];
      relations = [
        {
          id = "allow-vlan2-to-vlan2-dns";
          priority = 80;
          from = {
            kind = "tenant";
            name = "vlan2";
          };
          to = {
            kind = "service";
            name = "vlan2-dns";
          };
          trafficType = "dns";
          action = "allow";
        }
        {
          id = "allow-vlan7-to-vlan7-dns";
          priority = 81;
          from = {
            kind = "tenant";
            name = "vlan7";
          };
          to = {
            kind = "service";
            name = "vlan7-dns";
          };
          trafficType = "dns";
          action = "allow";
        }
        {
          id = "allow-vlan2-dns-to-wan";
          priority = 90;
          from = {
            kind = "service";
            name = "vlan2-dns";
          };
          to = {
            kind = "external";
            name = "wan";
            uplinks = [ "wan" ];
          };
          trafficType = "dns";
          action = "allow";
        }
        {
          id = "allow-vlan7-dns-to-wan";
          priority = 91;
          from = {
            kind = "service";
            name = "vlan7-dns";
          };
          to = {
            kind = "external";
            name = "wan";
            uplinks = [ "wan" ];
          };
          trafficType = "dns";
          action = "allow";
        }
        (allowTenantToWan "vlan2" 100)
        (allowTenantToWan "vlan7" 110)
      ];

      interfaceTags = {
        tenant-vlan2 = "vlan2";
        tenant-vlan7 = "vlan7";
        external-wan = "wan";
        service-vlan2-dns = "vlan2-dns";
        service-vlan7-dns = "vlan7-dns";
      };
    };

    topology = {
      nodes = {
        core = {
          role = "core";

          uplinks = {
            wan = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ ];
            };
          };
        };

        upstream-selector = {
          role = "upstream-selector";
        };

        policy = {
          role = "policy";
        };

        downstream-selector = {
          role = "downstream-selector";
        };

        access-vlan2 = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "vlan2";
            }
          ];
        };

        access-vlan7 = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "vlan7";
            }
          ];
        };
      };

      links = [
        [
          "core"
          "upstream-selector"
        ]
        [
          "upstream-selector"
          "policy"
        ]
        [
          "policy"
          "downstream-selector"
        ]
        [
          "downstream-selector"
          "access-vlan2"
        ]
        [
          "downstream-selector"
          "access-vlan7"
        ]
      ];
    };
  };
}
