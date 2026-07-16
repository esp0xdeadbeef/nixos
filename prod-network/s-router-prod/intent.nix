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

    {
      name = "nebula";
      match = [
        {
          proto = "udp";
          dports = [ 4242 ];
          family = "any";
        }
        {
          proto = "tcp";
          dports = [ 4242 ];
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
      returnBehavior = "symmetric";
    };

  runtimeIpv6Prefix = tenant: slot: {
    allocation = "runtime";
    family = "ipv6";
    name = "${tenant}-public";
    delegatedPrefixLength = 48;
    perTenantPrefixLength = 64;
    inherit slot;
    sourceFile = "/run/secrets/subnet-ipv6-${tenant}";
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
          routedPrefixes = [
            (runtimeIpv6Prefix "vlan2" 2)
          ];
        }
        {
          kind = "tenant";
          name = "vlan3";
          ipv4 = "192.168.3.0/24";
          ipv6 = "fd42:dead:beef:3::/64";
          routedPrefixes = [
            (runtimeIpv6Prefix "vlan3" 3)
          ];
        }
        {
          kind = "tenant";
          name = "vlan7";
          ipv4 = "192.168.2.0/24";
          ipv6 = "fd42:dead:beef:7::/64";
          routedPrefixes = [
            (runtimeIpv6Prefix "vlan7" 7)
          ];
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
          name = "vlan3-dns";
          tenant = "vlan3";
          ipv4 = [ "192.168.3.1" ];
          ipv6 = [ "fd42:dead:beef:3::1" ];
        }
        {
          kind = "host";
          name = "s-nebula-container";
          tenant = "vlan3";
          ipv4 = [ "192.168.3.10" ];
          ipv6 = [ "fd42:dead:beef:3::1337:dead:beef" ];
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
          name = "vlan3-dns";
          providers = [ "vlan3-dns" ];
          trafficType = "dns";
        }
        {
          name = "vlan7-dns";
          providers = [ "vlan7-dns" ];
          trafficType = "dns";
        }
        {
          name = "s-nebula-container";
          providers = [ "s-nebula-container" ];
          trafficType = "nebula";
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
          returnBehavior = "symmetric";
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
          returnBehavior = "symmetric";
        }
        {
          id = "allow-vlan3-to-vlan3-dns";
          priority = 82;
          from = {
            kind = "tenant";
            name = "vlan3";
          };
          to = {
            kind = "service";
            name = "vlan3-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "deny-vlan3-to-vlan2";
          priority = 84;
          from = {
            kind = "tenant";
            name = "vlan3";
          };
          to = {
            kind = "tenant";
            name = "vlan2";
          };
          trafficType = "any";
          action = "deny";
        }
        {
          id = "allow-vlan2-to-vlan3";
          priority = 85;
          from = {
            kind = "tenant";
            name = "vlan2";
          };
          to = {
            kind = "tenant";
            name = "vlan3";
          };
          trafficType = "any";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-wan-to-s-nebula-container";
          priority = 95;
          from = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          to = {
            kind = "service";
            name = "s-nebula-container";
          };
          trafficType = "nebula";
          action = "allow";
          publicIngressTupleAuthority = {
            sourceScope = "internet";
            publicSurface = "wan";
            targetService = "s-nebula-container";
            targetEndpoint = "s-nebula-container";
            targetPort = 4242;
            returnBehavior = "stateful-return";
            sourcePreservation = "rewritten";
            translationMode = "napt";
            hairpin = "not-modeled";
            asymmetricRouting = "not-allowed";
            tuples = [
              {
                protocol = "udp";
                publicPort = 4242;
              }
              {
                protocol = "tcp";
                publicPort = 4242;
              }
            ];
          };
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
          returnBehavior = "symmetric";
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
          returnBehavior = "symmetric";
        }
        (allowTenantToWan "vlan2" 100)
        (allowTenantToWan "vlan7" 110)
      ];

      interfaceTags = {
        tenant-vlan2 = "vlan2";
        tenant-vlan3 = "vlan3";
        tenant-vlan7 = "vlan7";
        external-wan = "wan";
        service-s-nebula-container = "s-nebula-container";
        service-vlan2-dns = "vlan2-dns";
        service-vlan3-dns = "vlan3-dns";
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
              ipv6 = [ "::/0" ];
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

        access-vlan3 = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "vlan3";
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
          "access-vlan3"
        ]
        [
          "downstream-selector"
          "access-vlan7"
        ]
      ];
    };
  };
}
