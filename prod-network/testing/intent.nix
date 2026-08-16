let
  trafficTypes = [
    {
      name = "icmp";
      match = [
        {
          proto = "icmp";
          family = "ipv4";
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
      name = "wireguard-1637";
      match = [
        {
          proto = "udp";
          dports = [ 1637 ];
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
  esp0xdeadbeef.neon = {
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
        {
          kind = "tenant";
          name = "vlan8";
          ipv4 = "192.168.8.0/24";
          ipv6 = "fd42:dead:beef:8::/64";
          routedPrefixes = [
            (runtimeIpv6Prefix "vlan8" 8)
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
        {
          kind = "host";
          name = "vlan8-dns";
          tenant = "vlan8";
          ipv4 = [ "192.168.8.1" ];
          ipv6 = [ "fd42:dead:beef:8::1" ];
        }
      ];
    };

    hostManagement = {
      required = true;
      interface = "vlan2";
      purpose = "hardware-management";
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
          name = "vlan8-dns";
          providers = [ "vlan8-dns" ];
          trafficType = "dns";
        }
        {
          name = "s-nebula-container";
          providers = [ "s-nebula-container" ];
          trafficType = "nebula";
        }
        {
          name = "s-nebula-container-icmp";
          providers = [ "s-nebula-container" ];
          trafficType = "icmp";
        }
      ];
      relations = [
        {
          # VLAN 2's resolver asks VLAN 3's resolver only for VLAN 3-owned
          # local data. The provider ACL remains refuse_non_local, so this
          # relation cannot expose VLAN 3 recursion or transitive egress.
          id = "allow-vlan2-dns-to-vlan3-dns";
          priority = 78;
          from = {
            kind = "service";
            name = "vlan2-dns";
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
          id = "allow-vlan8-to-vlan8-dns";
          priority = 86;
          from = {
            kind = "tenant";
            name = "vlan8";
          };
          to = {
            kind = "service";
            name = "vlan8-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          # VLAN 3's local resolver may query only VLAN 2's DNS service. The
          # resolver runtime narrows this further to the lan. namespaces, and
          # VLAN 2 serves this source with refuse_non_local so it cannot borrow
          # VLAN 2's recursive path to core/the Internet.
          id = "allow-vlan3-dns-to-vlan2-dns";
          priority = 79;
          from = {
            kind = "service";
            name = "vlan3-dns";
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
          id = "allow-vlan2-to-s-nebula-container-icmp";
          priority = 83;
          from = {
            kind = "tenant";
            name = "vlan2";
          };
          to = {
            kind = "service";
            name = "s-nebula-container-icmp";
          };
          trafficType = "icmp";
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
          # TEMPORARY compiler projection: keep this legacy relation until the
          # address-free recursiveDnsIntent can materialize the same fabric
          # lane without removing unrelated IPv6 policy-route units. Access
          # Unbound does not use public forwarders; inventory pins it to core.
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
          # See allow-vlan2-dns-to-wan: this preserves the compiler's VLAN 7
          # route projection only; the rendered resolver points solely to core.
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
        {
          # See allow-vlan2-dns-to-wan: temporary compiler projection for VLAN 8.
          id = "allow-vlan8-dns-to-wan";
          priority = 93;
          from = {
            kind = "service";
            name = "vlan8-dns";
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
        (allowTenantToWan "vlan8" 120)
      ];

      interfaceTags = {
        tenant-vlan2 = "vlan2";
        tenant-vlan3 = "vlan3";
        tenant-vlan7 = "vlan7";
        tenant-vlan8 = "vlan8";
        external-wan = "wan";
        service-s-nebula-container = "s-nebula-container";
        service-vlan2-dns = "vlan2-dns";
        service-vlan3-dns = "vlan3-dns";
        service-vlan7-dns = "vlan7-dns";
        service-vlan8-dns = "vlan8-dns";
      };
    };

    # Desired FS-540 recursive DNS contract. The active communication contract
    # temporarily retains its legacy service-to-WAN relations because removing
    # them also removes unrelated IPv6 policy-route units. Inventory points the
    # access resolvers only at core; preserve these explicit service-origin
    # relations as the address-free target contract for the future SMS closure.
    recursiveDnsIntent = {
      services = [
        {
          name = "core-dns";
          providerNode = "core";
          addressAuthority = "model-allocated-service-prefix";
          trafficType = "dns";
        }
      ];

      relations = [
        {
          # VLAN 2 clients may query the internal core resolver directly. This
          # is a normal supported path: core remains bound only to its
          # upstream-selector-facing service surface, and VLAN 3 deliberately
          # has no equivalent relation.
          id = "allow-vlan2-to-core-dns";
          priority = 87;
          from = {
            kind = "tenant";
            name = "vlan2";
          };
          to = {
            kind = "service";
            name = "core-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-vlan2-dns-to-core-dns";
          priority = 88;
          from = {
            kind = "service";
            name = "vlan2-dns";
          };
          to = {
            kind = "service";
            name = "core-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-vlan7-dns-to-core-dns";
          priority = 89;
          from = {
            kind = "service";
            name = "vlan7-dns";
          };
          to = {
            kind = "service";
            name = "core-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-core-dns-to-wan";
          priority = 90;
          from = {
            kind = "service";
            name = "core-dns";
          };
          to = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "deny-vlan2-dns-to-wan";
          priority = 92;
          from = {
            kind = "service";
            name = "vlan2-dns";
          };
          to = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          trafficType = "dns";
          action = "deny";
        }
        {
          id = "deny-vlan7-dns-to-wan";
          priority = 93;
          from = {
            kind = "service";
            name = "vlan7-dns";
          };
          to = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          trafficType = "dns";
          action = "deny";
        }
        {
          id = "allow-vlan8-dns-to-core-dns";
          priority = 94;
          from = {
            kind = "service";
            name = "vlan8-dns";
          };
          to = {
            kind = "service";
            name = "core-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
      ];

      bindings = [
        {
          requesterScope = {
            kind = "service";
            name = "vlan2-dns";
          };
          advertisedResolver = {
            kind = "service";
            name = "vlan2-dns";
          };
          resolverSource = "local-recursive";
          upstreamResolver = {
            kind = "service";
            name = "core-dns";
            node = "core";
          };
          resolverPath = [
            "access-vlan2"
            "downstream-selector"
            "policy"
            "upstream-selector"
            "core"
          ];
          egressSurface = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          returnBehavior = "symmetric";
          allowedAddressFamilies = [
            "ipv4"
            "ipv6"
          ];
          directPublicFallback = false;
        }
        {
          requesterScope = {
            kind = "service";
            name = "vlan7-dns";
          };
          advertisedResolver = {
            kind = "service";
            name = "vlan7-dns";
          };
          resolverSource = "local-recursive";
          upstreamResolver = {
            kind = "service";
            name = "core-dns";
            node = "core";
          };
          resolverPath = [
            "access-vlan7"
            "downstream-selector"
            "policy"
            "upstream-selector"
            "core"
          ];
          egressSurface = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          returnBehavior = "symmetric";
          allowedAddressFamilies = [
            "ipv4"
            "ipv6"
          ];
          directPublicFallback = false;
        }
        {
          requesterScope = {
            kind = "service";
            name = "vlan8-dns";
          };
          advertisedResolver = {
            kind = "service";
            name = "vlan8-dns";
          };
          resolverSource = "local-recursive";
          upstreamResolver = {
            kind = "service";
            name = "core-dns";
            node = "core";
          };
          resolverPath = [
            "access-vlan8"
            "downstream-selector"
            "policy"
            "upstream-selector"
            "core"
          ];
          egressSurface = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          returnBehavior = "symmetric";
          allowedAddressFamilies = [
            "ipv4"
            "ipv6"
          ];
          directPublicFallback = false;
        }
      ];
    };

    # Desired local namespace-sharing contract. The active relation above
    # materializes the access-to-access route and firewall path; the pinned SMS
    # schema models only one requester/authority pair. VLAN 3 therefore queries
    # VLAN 2 for the shared lan. namespace here, while a temporary NixOS override
    # expresses the reverse, exact-name VLAN 2 -> VLAN 3 authority lookup.
    localDnsSharingIntent = {
      namespace = "lan.";
      authority = {
        service = "vlan2-dns";
        records = [
          "vlan2-kea-local-data"
          "vlan3-static-local-data"
        ];
      };
      requester = {
        service = "vlan3-dns";
        allowedNamespaces = [
          "lan."
          "1.168.192.in-addr.arpa."
        ];
        recursion = false;
        publicFallback = false;
      };
      relation = {
        id = "allow-vlan3-dns-to-vlan2-dns";
        from = {
          kind = "service";
          name = "vlan3-dns";
        };
        to = {
          kind = "service";
          name = "vlan2-dns";
        };
        trafficType = "dns";
        returnBehavior = "symmetric";
        resolverPath = [
          "access-vlan3"
          "downstream-selector"
          "access-vlan2"
        ];
      };
      providerPolicy = {
        source = "vlan3-dns";
        action = "refuse_non_local";
      };
      lateralPolicy = {
        source = "vlan2";
        target = "vlan3-dns";
        localData = true;
        recursion = false;
        transitiveEgress = false;
        action = "refuse_non_local";
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

        access-vlan8 = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "vlan8";
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
        [
          "downstream-selector"
          "access-vlan8"
        ]
      ];
    };
  };

  esp0xdeadbeef.cobalt = {
    pools = {
      p2p = {
        ipv4 = "10.1.0.0/24";
        ipv6 = "fd42:dead:beef:2000::/118";
      };

      loopback = {
        ipv4 = "10.1.1.0/24";
        ipv6 = "fd42:dead:beef:2900::/118";
      };
    };

    ownership = {
      prefixes = [
        {
          kind = "tenant";
          name = "svc";
          ipv4 = "10.2.20.0/24";
          ipv6 = "fd42:dead:beef:c14::/64";
        }
        {
          kind = "tenant";
          name = "clients";
          ipv4 = "10.2.30.0/24";
          ipv6 = "fd42:dead:beef:c1e::/64";
        }
        {
          kind = "tenant";
          name = "iot";
          ipv4 = "10.2.50.0/24";
          ipv6 = "fd42:dead:beef:c32::/64";
        }
        {
          kind = "tenant";
          name = "iot-srv";
          ipv4 = "10.2.51.0/24";
          ipv6 = "fd42:dead:beef:c33::/64";
        }
        {
          kind = "tenant";
          name = "dmz";
          ipv4 = "10.2.60.0/24";
          ipv6 = "fd42:dead:beef:c3c::/64";
        }
        {
          kind = "tenant";
          name = "clients-vpn";
          ipv4 = "10.2.31.0/24";
          ipv6 = "fd42:dead:beef:c1f::/64";
        }
      ];

      endpoints = [
        {
          kind = "host";
          name = "cobalt-svc-dns";
          tenant = "svc";
          ipv4 = [ "10.2.20.1" ];
        }
        {
          kind = "host";
          name = "cobalt-clients-dns";
          tenant = "clients";
          ipv4 = [ "10.2.30.1" ];
        }
        {
          kind = "host";
          name = "cobalt-iot-dns";
          tenant = "iot";
          ipv4 = [ "10.2.50.1" ];
        }
        {
          kind = "host";
          name = "cobalt-iot-srv-dns";
          tenant = "iot-srv";
          ipv4 = [ "10.2.51.1" ];
        }
        {
          kind = "host";
          name = "cobalt-dmz-dns";
          tenant = "dmz";
          ipv4 = [ "10.2.60.1" ];
        }
        {
          kind = "host";
          name = "cobalt-clients-vpn-dns";
          tenant = "clients-vpn";
          ipv4 = [ "10.2.31.1" ];
        }
      ];
    };

    hostManagement = {
      required = true;
      interface = "vlan300";
      purpose = "hardware-management";
    };

    communicationContract = {
      inherit trafficTypes;
      services = [
        {
          name = "svc-dns";
          providers = [ "cobalt-svc-dns" ];
          trafficType = "dns";
        }
        {
          name = "clients-dns";
          providers = [ "cobalt-clients-dns" ];
          trafficType = "dns";
        }
        {
          name = "iot-dns";
          providers = [ "cobalt-iot-dns" ];
          trafficType = "dns";
        }
        {
          name = "iot-srv-dns";
          providers = [ "cobalt-iot-srv-dns" ];
          trafficType = "dns";
        }
        {
          name = "dmz-dns";
          providers = [ "cobalt-dmz-dns" ];
          trafficType = "dns";
        }
        {
          name = "clients-vpn-dns";
          providers = [ "cobalt-clients-vpn-dns" ];
          trafficType = "dns";
        }
      ];

      relations = [
        {
          id = "allow-clients-dns-to-dmz-dns";
          priority = 78;
          from = {
            kind = "service";
            name = "clients-dns";
          };
          to = {
            kind = "service";
            name = "dmz-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-dmz-dns-to-clients-dns";
          priority = 79;
          from = {
            kind = "service";
            name = "dmz-dns";
          };
          to = {
            kind = "service";
            name = "clients-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-to-clients-dns";
          priority = 80;
          from = {
            kind = "tenant";
            name = "clients";
          };
          to = {
            kind = "service";
            name = "clients-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-svc-to-svc-dns";
          priority = 81;
          from = {
            kind = "tenant";
            name = "svc";
          };
          to = {
            kind = "service";
            name = "svc-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-dmz-to-dmz-dns";
          priority = 82;
          from = {
            kind = "tenant";
            name = "dmz";
          };
          to = {
            kind = "service";
            name = "dmz-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "deny-dmz-to-clients";
          priority = 84;
          from = {
            kind = "tenant";
            name = "dmz";
          };
          to = {
            kind = "tenant";
            name = "clients";
          };
          trafficType = "any";
          action = "deny";
        }
        {
          id = "allow-clients-to-dmz";
          priority = 85;
          from = {
            kind = "tenant";
            name = "clients";
          };
          to = {
            kind = "tenant";
            name = "dmz";
          };
          trafficType = "any";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-to-iot-dns";
          priority = 86;
          from = {
            kind = "tenant";
            name = "iot";
          };
          to = {
            kind = "service";
            name = "iot-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-srv-to-iot-srv-dns";
          priority = 87;
          from = {
            kind = "tenant";
            name = "iot-srv";
          };
          to = {
            kind = "service";
            name = "iot-srv-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-vpn-to-clients-vpn-dns";
          priority = 87;
          from = {
            kind = "tenant";
            name = "clients-vpn";
          };
          to = {
            kind = "service";
            name = "clients-vpn-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-dns-to-wan";
          priority = 90;
          from = {
            kind = "service";
            name = "clients-dns";
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
          id = "allow-svc-dns-to-wan";
          priority = 91;
          from = {
            kind = "service";
            name = "svc-dns";
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
          id = "allow-iot-dns-to-wan";
          priority = 93;
          from = {
            kind = "service";
            name = "iot-dns";
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
          id = "allow-iot-srv-dns-to-wan";
          priority = 94;
          from = {
            kind = "service";
            name = "iot-srv-dns";
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
        (allowTenantToWan "clients" 100)
        (allowTenantToWan "svc" 110)
        (allowTenantToWan "iot" 120)
        (allowTenantToWan "iot-srv" 130)
        {
          id = "allow-clients-vpn-to-onyx";
          priority = 85;
          from = {
            kind = "tenant";
            name = "clients-vpn";
          };
          to = {
            kind = "external";
            uplinks = [ "onyx" ];
          };
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-onyx-uplink-to-wan";
          priority = 140;
          from = {
            kind = "external";
            name = "onyx";
          };
          to = {
            kind = "external";
            name = "wan";
            uplinks = [ "wan" ];
          };
          trafficType = "wireguard-1637";
          action = "allow";
          returnBehavior = "symmetric";
        }
      ];
    };

    interfaceTags = {
      tenant-svc = "svc";
      tenant-clients = "clients";
      tenant-iot = "iot";
      tenant-iot-srv = "iot-srv";
      tenant-dmz = "dmz";
      tenant-clients-vpn = "clients-vpn";
      external-wan = "wan";
      service-svc-dns = "svc-dns";
      service-clients-dns = "clients-dns";
      service-clients-vpn-dns = "clients-vpn-dns";
      service-iot-dns = "iot-dns";
      service-iot-srv-dns = "iot-srv-dns";
      service-dmz-dns = "dmz-dns";
    };

    recursiveDnsIntent = {
      services = [
        {
          name = "core-dns";
          providerNode = "core";
          addressAuthority = "model-allocated-service-prefix";
          trafficType = "dns";
        }
        {
          name = "onyx-dns";
          providerNode = "core-vpn-onyx";
          addressAuthority = "model-allocated-service-prefix";
          trafficType = "dns";
        }
      ];

      relations = [
        {
          id = "allow-clients-vpn-to-onyx-dns";
          priority = 86;
          from = {
            kind = "tenant";
            name = "clients-vpn";
          };
          to = {
            kind = "service";
            name = "onyx-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-onyx-dns-to-onyx";
          priority = 90;
          from = {
            kind = "service";
            name = "onyx-dns";
          };
          to = {
            kind = "external";
            uplinks = [ "onyx" ];
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-to-core-dns";
          priority = 87;
          from = {
            kind = "tenant";
            name = "clients";
          };
          to = {
            kind = "service";
            name = "core-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-dns-to-core-dns";
          priority = 88;
          from = {
            kind = "service";
            name = "clients-dns";
          };
          to = {
            kind = "service";
            name = "core-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-svc-dns-to-core-dns";
          priority = 89;
          from = {
            kind = "service";
            name = "svc-dns";
          };
          to = {
            kind = "service";
            name = "core-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-core-dns-to-wan";
          priority = 90;
          from = {
            kind = "service";
            name = "core-dns";
          };
          to = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "deny-clients-dns-to-wan";
          priority = 92;
          from = {
            kind = "service";
            name = "clients-dns";
          };
          to = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          trafficType = "dns";
          action = "deny";
        }
        {
          id = "deny-svc-dns-to-wan";
          priority = 93;
          from = {
            kind = "service";
            name = "svc-dns";
          };
          to = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          trafficType = "dns";
          action = "deny";
        }
        {
          id = "allow-iot-dns-to-core-dns";
          priority = 94;
          from = {
            kind = "service";
            name = "iot-dns";
          };
          to = {
            kind = "service";
            name = "core-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-srv-dns-to-core-dns";
          priority = 95;
          from = {
            kind = "service";
            name = "iot-srv-dns";
          };
          to = {
            kind = "service";
            name = "core-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-vpn-dns-to-onyx-dns";
          priority = 96;
          from = {
            kind = "service";
            name = "clients-vpn-dns";
          };
          to = {
            kind = "service";
            name = "onyx-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
      ];

      bindings = [
        {
          requesterScope = {
            kind = "service";
            name = "clients-dns";
          };
          advertisedResolver = {
            kind = "service";
            name = "clients-dns";
          };
          resolverSource = "local-recursive";
          upstreamResolver = {
            kind = "service";
            name = "core-dns";
            node = "core";
          };
          resolverPath = [
            "access-clients"
            "downstream-selector"
            "policy"
            "upstream-selector"
            "core"
          ];
          egressSurface = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          returnBehavior = "symmetric";
          allowedAddressFamilies = [ "ipv4" "ipv6" ];
          directPublicFallback = false;
        }
        {
          requesterScope = {
            kind = "service";
            name = "svc-dns";
          };
          advertisedResolver = {
            kind = "service";
            name = "svc-dns";
          };
          resolverSource = "local-recursive";
          upstreamResolver = {
            kind = "service";
            name = "core-dns";
            node = "core";
          };
          resolverPath = [
            "access-svc"
            "downstream-selector"
            "policy"
            "upstream-selector"
            "core"
          ];
          egressSurface = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          returnBehavior = "symmetric";
          allowedAddressFamilies = [ "ipv4" "ipv6" ];
          directPublicFallback = false;
        }
        {
          requesterScope = {
            kind = "service";
            name = "iot-dns";
          };
          advertisedResolver = {
            kind = "service";
            name = "iot-dns";
          };
          resolverSource = "local-recursive";
          upstreamResolver = {
            kind = "service";
            name = "core-dns";
            node = "core";
          };
          resolverPath = [
            "access-iot"
            "downstream-selector"
            "policy"
            "upstream-selector"
            "core"
          ];
          egressSurface = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          returnBehavior = "symmetric";
          allowedAddressFamilies = [ "ipv4" "ipv6" ];
          directPublicFallback = false;
        }
        {
          requesterScope = {
            kind = "service";
            name = "iot-srv-dns";
          };
          advertisedResolver = {
            kind = "service";
            name = "iot-srv-dns";
          };
          resolverSource = "local-recursive";
          upstreamResolver = {
            kind = "service";
            name = "core-dns";
            node = "core";
          };
          resolverPath = [
            "access-iot-srv"
            "downstream-selector"
            "policy"
            "upstream-selector"
            "core"
          ];
          egressSurface = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          returnBehavior = "symmetric";
          allowedAddressFamilies = [ "ipv4" "ipv6" ];
          directPublicFallback = false;
        }
        {
          requesterScope = {
            kind = "service";
            name = "clients-vpn-dns";
          };
          advertisedResolver = {
            kind = "service";
            name = "clients-vpn-dns";
          };
          resolverSource = "local-recursive";
          upstreamResolver = {
            kind = "service";
            name = "onyx-dns";
            node = "core-vpn-onyx";
          };
          resolverPath = [
            "access-clients-vpn"
            "downstream-selector"
            "policy"
            "upstream-selector"
            "core-vpn-onyx"
          ];
          egressSurface = {
            kind = "external";
            uplinks = [ "onyx" ];
          };
          returnBehavior = "symmetric";
          allowedAddressFamilies = [ "ipv4" "ipv6" ];
          directPublicFallback = false;
        }
      ];
    };

    localDnsSharingIntent = {
      namespace = "home.arpa.";
      authority = {
        service = "clients-dns";
        records = [
          "clients-kea-local-data"
          "dmz-static-local-data"
        ];
      };
      requester = {
        service = "dmz-dns";
        allowedNamespaces = [
          "home.arpa."
          "30.2.10.in-addr.arpa."
        ];
        recursion = false;
        publicFallback = false;
      };
      relation = {
        id = "allow-dmz-dns-to-clients-dns";
        from = {
          kind = "service";
          name = "dmz-dns";
        };
        to = {
          kind = "service";
          name = "clients-dns";
        };
        trafficType = "dns";
        returnBehavior = "symmetric";
        resolverPath = [
          "access-dmz"
          "downstream-selector"
          "access-clients"
        ];
      };
      providerPolicy = {
        source = "dmz-dns";
        action = "refuse_non_local";
      };
      lateralPolicy = {
        source = "clients";
        target = "dmz-dns";
        localData = true;
        recursion = false;
        transitiveEgress = false;
        action = "refuse_non_local";
      };
    };

    topology = {
      nodes = {
        core = {
          role = "core";
          uplinks = {
            wan = {
              ipv4 = [ "0.0.0.0/0" ];
            };
          };
        };

        core-vpn-onyx = {
          role = "core";
          uplinks = {
            onyx = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "fd42:dead:feed:c1e::/64" ];
            };
          };
          attachments = [
            {
              kind = "tenant";
              name = "iot-srv";
            }
          ];
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

        access-svc = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "svc";
            }
          ];
        };

        access-clients = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "clients";
            }
          ];
        };

        access-iot = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "iot";
            }
          ];
        };

        access-iot-srv = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "iot-srv";
            }
          ];
        };

        access-dmz = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "dmz";
            }
          ];
        };

        access-clients-vpn = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "clients-vpn";
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
          "core-vpn-onyx"
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
          "access-svc"
        ]
        [
          "downstream-selector"
          "access-clients"
        ]
        [
          "downstream-selector"
          "access-dmz"
        ]
        [
          "downstream-selector"
          "access-iot-srv"
        ]
        [
          "downstream-selector"
          "access-iot"
        ]
        [
          "downstream-selector"
          "access-clients-vpn"
        ]
      ];
    };

    transport = {
      overlays = [
        {
          name = "onyx";
          terminateOn = [ "core-vpn-onyx" ];
          underlayAccess = {
            kind = "tenant";
            name = "iot-srv";
          };
        }
      ];
    };
  };
}
