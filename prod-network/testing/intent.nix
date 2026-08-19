let
  traceroutePorts = builtins.genList (x: 33434 + x) 90;

  trafficTypes = [
    {
      name = "icmp";
      match = [
        {
          proto = "icmp";
          family = "ipv4";
        }
        {
          proto = "icmpv6";
          family = "ipv6";
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

    {
      name = "tang";
      match = [
        {
          proto = "tcp";
          dports = [ 7500 ];
          family = "any";
        }
      ];
    }

    {
      name = "traceroute";
      match = [
        {
          proto = "udp";
          dports = traceroutePorts;
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
        uplinks = [ "wan" ];
      };
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
        {
          kind = "tenant";
          name = "neon-mgmt";
          ipv4 = "10.3.10.0/24";
          ipv6 = "fd42:dead:beef:310::/64";
        }
        {
          kind = "tenant";
          name = "neon-svc";
          ipv4 = "10.3.20.0/24";
          ipv6 = "fd42:dead:beef:320::/64";
        }
        {
          kind = "tenant";
          name = "neon-clients";
          ipv4 = "10.3.30.0/24";
          ipv6 = "fd42:dead:beef:330::/64";
        }
        {
          kind = "tenant";
          name = "neon-iot";
          ipv4 = "10.3.50.0/24";
          ipv6 = "fd42:dead:beef:350::/64";
        }
        {
          kind = "tenant";
          name = "neon-iot-srv";
          ipv4 = "10.3.51.0/24";
          ipv6 = "fd42:dead:beef:351::/64";
        }
        {
          kind = "tenant";
          name = "neon-dmz";
          ipv4 = "10.3.60.0/24";
          ipv6 = "fd42:dead:beef:360::/64";
        }
        {
          kind = "tenant";
          name = "neon-unlock";
          ipv4 = "10.3.90.0/24";
          ipv6 = "fd42:dead:beef:390::/64";
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
        {
          kind = "host";
          name = "neon-mgmt-dns";
          tenant = "neon-mgmt";
          ipv4 = [ "10.3.10.1" ];
        }
        {
          kind = "host";
          name = "neon-svc-dns";
          tenant = "neon-svc";
          ipv4 = [ "10.3.20.1" ];
        }
        {
          kind = "host";
          name = "neon-clients-dns";
          tenant = "neon-clients";
          ipv4 = [ "10.3.30.1" ];
        }
        {
          kind = "host";
          name = "neon-iot-dns";
          tenant = "neon-iot";
          ipv4 = [ "10.3.50.1" ];
        }
        {
          kind = "host";
          name = "neon-iot-srv-dns";
          tenant = "neon-iot-srv";
          ipv4 = [ "10.3.51.1" ];
        }
        {
          kind = "host";
          name = "neon-dmz-dns";
          tenant = "neon-dmz";
          ipv4 = [ "10.3.60.1" ];
        }
        {
          kind = "host";
          name = "neon-unlock-dns";
          tenant = "neon-unlock";
          ipv4 = [ "10.3.90.1" ];
        }
        {
          kind = "host";
          name = "neon-tang";
          tenant = "neon-unlock";
          ipv4 = [ "10.3.90.10" ];
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
        {
          name = "mgmt-dns";
          providers = [ "neon-mgmt-dns" ];
          trafficType = "dns";
        }
        {
          name = "svc-dns";
          providers = [ "neon-svc-dns" ];
          trafficType = "dns";
        }
        {
          name = "clients-dns";
          providers = [ "neon-clients-dns" ];
          trafficType = "dns";
        }
        {
          name = "iot-dns";
          providers = [ "neon-iot-dns" ];
          trafficType = "dns";
        }
        {
          name = "iot-srv-dns";
          providers = [ "neon-iot-srv-dns" ];
          trafficType = "dns";
        }
        {
          name = "dmz-dns";
          providers = [ "neon-dmz-dns" ];
          trafficType = "dns";
        }
        {
          name = "unlock-dns";
          providers = [ "neon-unlock-dns" ];
          trafficType = "dns";
        }
        {
          name = "tang";
          providers = [ "neon-tang" ];
          trafficType = "tang";
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
        (allowTenantToWan "vlan2" 100)
        (allowTenantToWan "vlan7" 110)
        (allowTenantToWan "vlan8" 120)
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
          id = "allow-clients-dns-to-unlock-dns";
          priority = 81;
          from = {
            kind = "service";
            name = "clients-dns";
          };
          to = {
            kind = "service";
            name = "unlock-dns";
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
            name = "neon-clients";
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
            name = "neon-svc";
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
            name = "neon-dmz";
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
            name = "neon-dmz";
          };
          to = {
            kind = "tenant";
            name = "neon-clients";
          };
          trafficType = "any";
          action = "deny";
        }
        {
          id = "allow-clients-to-dmz";
          priority = 85;
          from = {
            kind = "tenant";
            name = "neon-clients";
          };
          to = {
            kind = "tenant";
            name = "neon-dmz";
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
            name = "neon-iot";
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
            name = "neon-iot-srv";
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
          id = "allow-unlock-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "neon-unlock";
          };
          to = {
            kind = "service";
            name = "tang";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "neon-clients";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-svc-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "neon-svc";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "neon-iot";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-srv-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "neon-iot-srv";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-dmz-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "neon-dmz";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-mgmt-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "neon-mgmt";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-to-tang-icmp";
          priority = 84;
          from = {
            kind = "tenant";
            name = "neon-clients";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "icmp";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-svc-to-tang-icmp";
          priority = 84;
          from = {
            kind = "tenant";
            name = "neon-svc";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "icmp";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-to-tang-icmp";
          priority = 84;
          from = {
            kind = "tenant";
            name = "neon-iot";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "icmp";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-srv-to-tang-icmp";
          priority = 84;
          from = {
            kind = "tenant";
            name = "neon-iot-srv";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "icmp";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-dmz-to-tang-icmp";
          priority = 84;
          from = {
            kind = "tenant";
            name = "neon-dmz";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "icmp";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-mgmt-to-tang-icmp";
          priority = 84;
          from = {
            kind = "tenant";
            name = "neon-mgmt";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "icmp";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-to-tang-traceroute";
          priority = 83;
          from = {
            kind = "tenant";
            name = "neon-clients";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "traceroute";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-svc-to-tang-traceroute";
          priority = 83;
          from = {
            kind = "tenant";
            name = "neon-svc";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "traceroute";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-to-tang-traceroute";
          priority = 83;
          from = {
            kind = "tenant";
            name = "neon-iot";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "traceroute";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-srv-to-tang-traceroute";
          priority = 83;
          from = {
            kind = "tenant";
            name = "neon-iot-srv";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "traceroute";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-dmz-to-tang-traceroute";
          priority = 83;
          from = {
            kind = "tenant";
            name = "neon-dmz";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "traceroute";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-mgmt-to-tang-traceroute";
          priority = 83;
          from = {
            kind = "tenant";
            name = "neon-mgmt";
          };
          to = {
            kind = "tenant";
            name = "neon-unlock";
          };
          trafficType = "traceroute";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-mgmt-to-mgmt-dns";
          priority = 88;
          from = {
            kind = "tenant";
            name = "neon-mgmt";
          };
          to = {
            kind = "service";
            name = "mgmt-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        (allowTenantToWan "neon-clients" 100)
        (allowTenantToWan "neon-svc" 110)
        (allowTenantToWan "neon-iot" 120)
        (allowTenantToWan "neon-iot-srv" 130)
        (allowTenantToWan "neon-mgmt" 140)
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
        tenant-neon-mgmt = "neon-mgmt";
        tenant-neon-svc = "neon-svc";
        tenant-neon-clients = "neon-clients";
        tenant-neon-iot = "neon-iot";
        tenant-neon-iot-srv = "neon-iot-srv";
        tenant-neon-dmz = "neon-dmz";
        tenant-neon-unlock = "neon-unlock";
        service-mgmt-dns = "mgmt-dns";
        service-svc-dns = "svc-dns";
        service-clients-dns = "clients-dns";
        service-iot-dns = "iot-dns";
        service-iot-srv-dns = "iot-srv-dns";
        service-dmz-dns = "dmz-dns";
        service-unlock-dns = "unlock-dns";
        service-tang = "tang";
      };
    };

    # FS-540 recursive DNS contract. Every access resolver (legacy vlan2/7/8
    # and the new plane lanes) forwards to core-dns, and core-dns is the only
    # modeled DNS egress surface to the WAN. Direct service-to-WAN DNS allows
    # are intentionally absent from the communication contract: alongside
    # allow-core-dns-to-wan they describe a second egress path for the same
    # resolver, and the forwarding model's transitive egress closure cannot
    # normalize that dual path (it renders a self-referential policy-container
    # config). The inventory pins each access Unbound resolver to core-dns.
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
        {
          id = "allow-clients-to-core-dns";
          priority = 87;
          from = {
            kind = "tenant";
            name = "neon-clients";
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
          id = "allow-mgmt-to-core-dns";
          priority = 89;
          from = {
            kind = "tenant";
            name = "neon-mgmt";
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
          id = "allow-mgmt-dns-to-core-dns";
          priority = 90;
          from = {
            kind = "service";
            name = "mgmt-dns";
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
          allowedAddressFamilies = [
            "ipv4"
            "ipv6"
          ];
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
          allowedAddressFamilies = [
            "ipv4"
            "ipv6"
          ];
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
          allowedAddressFamilies = [
            "ipv4"
            "ipv6"
          ];
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
          allowedAddressFamilies = [
            "ipv4"
            "ipv6"
          ];
          directPublicFallback = false;
        }
        {
          requesterScope = {
            kind = "service";
            name = "mgmt-dns";
          };
          advertisedResolver = {
            kind = "service";
            name = "mgmt-dns";
          };
          resolverSource = "local-recursive";
          upstreamResolver = {
            kind = "service";
            name = "core-dns";
            node = "core";
          };
          resolverPath = [
            "access-mgmt"
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
    localDnsSharingIntent = [
      {
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
      }
      {
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
            "30.3.10.in-addr.arpa."
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
          source = "neon-clients";
          target = "dmz-dns";
          localData = true;
          recursion = false;
          transitiveEgress = false;
          action = "refuse_non_local";
        };
      }
      {
        namespace = "home.arpa.";
        authority = {
          service = "unlock-dns";
          records = [
            "unlock-static-local-data"
          ];
        };
        requester = {
          service = "clients-dns";
          allowedNamespaces = [
            "unlock.home.arpa."
            "90.3.10.in-addr.arpa."
          ];
          recursion = false;
          publicFallback = false;
        };
        relation = {
          id = "allow-clients-dns-to-unlock-dns";
          from = {
            kind = "service";
            name = "clients-dns";
          };
          to = {
            kind = "service";
            name = "unlock-dns";
          };
          trafficType = "dns";
          returnBehavior = "symmetric";
          resolverPath = [
            "access-clients"
            "downstream-selector"
            "access-unlock"
          ];
        };
        providerPolicy = {
          source = "clients-dns";
          action = "refuse_non_local";
        };
        lateralPolicy = {
          source = "neon-unlock";
          target = "clients-dns";
          localData = true;
          recursion = false;
          transitiveEgress = false;
          action = "refuse_non_local";
        };
      }
    ];

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
        access-mgmt = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "neon-mgmt";
            }
          ];
        };
        access-svc = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "neon-svc";
            }
          ];
        };
        access-clients = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "neon-clients";
            }
          ];
        };
        access-iot = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "neon-iot";
            }
          ];
        };
        access-iot-srv = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "neon-iot-srv";
            }
          ];
        };
        access-dmz = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "neon-dmz";
            }
          ];
        };
        access-unlock = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "neon-unlock";
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
        [
          "downstream-selector"
          "access-mgmt"
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
          "access-iot"
        ]
        [
          "downstream-selector"
          "access-iot-srv"
        ]
        [
          "downstream-selector"
          "access-dmz"
        ]
        [
          "downstream-selector"
          "access-unlock"
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
          name = "cobalt-svc";
          ipv4 = "10.2.20.0/24";
          ipv6 = "fd42:dead:beef:220::/64";
        }
        {
          kind = "tenant";
          name = "cobalt-clients";
          ipv4 = "10.2.30.0/24";
          ipv6 = "fd42:dead:beef:230::/64";
        }
        {
          kind = "tenant";
          name = "cobalt-iot";
          ipv4 = "10.2.50.0/24";
          ipv6 = "fd42:dead:beef:250::/64";
        }
        {
          kind = "tenant";
          name = "cobalt-iot-srv";
          ipv4 = "10.2.51.0/24";
          ipv6 = "fd42:dead:beef:251::/64";
        }
        {
          kind = "tenant";
          name = "cobalt-dmz";
          ipv4 = "10.2.60.0/24";
          ipv6 = "fd42:dead:beef:260::/64";
        }
        {
          kind = "tenant";
          name = "cobalt-clients-vpn";
          ipv4 = "10.2.31.0/24";
          ipv6 = "fd42:dead:beef:231::/64";
        }
        {
          kind = "tenant";
          name = "cobalt-unlock";
          ipv4 = "10.2.90.0/24";
          ipv6 = "fd42:dead:beef:290::/64";
        }
        {
          kind = "tenant";
          name = "cobalt-mgmt";
          ipv4 = "10.2.10.0/24";
          ipv6 = "fd42:dead:beef:210::/64";
        }
      ];

      endpoints = [
        {
          kind = "host";
          name = "cobalt-svc-dns";
          tenant = "cobalt-svc";
          ipv4 = [ "10.2.20.1" ];
        }
        {
          kind = "host";
          name = "cobalt-clients-dns";
          tenant = "cobalt-clients";
          ipv4 = [ "10.2.30.1" ];
        }
        {
          kind = "host";
          name = "cobalt-iot-dns";
          tenant = "cobalt-iot";
          ipv4 = [ "10.2.50.1" ];
        }
        {
          kind = "host";
          name = "cobalt-iot-srv-dns";
          tenant = "cobalt-iot-srv";
          ipv4 = [ "10.2.51.1" ];
        }
        {
          kind = "host";
          name = "cobalt-dmz-dns";
          tenant = "cobalt-dmz";
          ipv4 = [ "10.2.60.1" ];
        }
        {
          kind = "host";
          name = "cobalt-clients-vpn-dns";
          tenant = "cobalt-clients-vpn";
          ipv4 = [ "10.2.31.1" ];
        }
        {
          kind = "host";
          name = "cobalt-tang";
          tenant = "cobalt-unlock";
          ipv4 = [ "10.2.90.10" ];
        }
        {
          kind = "host";
          name = "cobalt-mgmt-dns";
          tenant = "cobalt-mgmt";
          ipv4 = [ "10.2.10.1" ];
        }
        {
          kind = "host";
          name = "cobalt-unlock-dns";
          tenant = "cobalt-unlock";
          ipv4 = [ "10.2.90.1" ];
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
        {
          name = "tang";
          providers = [ "cobalt-tang" ];
          trafficType = "tang";
        }
        {
          name = "unlock-dns";
          providers = [ "cobalt-unlock-dns" ];
          trafficType = "dns";
        }
        {
          name = "mgmt-dns";
          providers = [ "cobalt-mgmt-dns" ];
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
          id = "allow-clients-dns-to-unlock-dns";
          priority = 81;
          from = {
            kind = "service";
            name = "clients-dns";
          };
          to = {
            kind = "service";
            name = "unlock-dns";
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
            name = "cobalt-clients";
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
            name = "cobalt-svc";
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
            name = "cobalt-dmz";
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
            name = "cobalt-dmz";
          };
          to = {
            kind = "tenant";
            name = "cobalt-clients";
          };
          trafficType = "any";
          action = "deny";
        }
        {
          id = "allow-clients-to-dmz";
          priority = 85;
          from = {
            kind = "tenant";
            name = "cobalt-clients";
          };
          to = {
            kind = "tenant";
            name = "cobalt-dmz";
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
            name = "cobalt-iot";
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
            name = "cobalt-iot-srv";
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
            name = "cobalt-clients-vpn";
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
          id = "allow-unlock-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          to = {
            kind = "service";
            name = "tang";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "cobalt-clients";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-svc-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "cobalt-svc";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "cobalt-iot";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-srv-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "cobalt-iot-srv";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-dmz-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "cobalt-dmz";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-vpn-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "cobalt-clients-vpn";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-mgmt-to-tang";
          priority = 85;
          from = {
            kind = "tenant";
            name = "cobalt-mgmt";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "tang";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-to-tang-icmp";
          priority = 84;
          from = {
            kind = "tenant";
            name = "cobalt-clients";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "icmp";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-svc-to-tang-icmp";
          priority = 84;
          from = {
            kind = "tenant";
            name = "cobalt-svc";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "icmp";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-to-tang-icmp";
          priority = 84;
          from = {
            kind = "tenant";
            name = "cobalt-iot";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "icmp";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-srv-to-tang-icmp";
          priority = 84;
          from = {
            kind = "tenant";
            name = "cobalt-iot-srv";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "icmp";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-dmz-to-tang-icmp";
          priority = 84;
          from = {
            kind = "tenant";
            name = "cobalt-dmz";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "icmp";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-vpn-to-tang-icmp";
          priority = 84;
          from = {
            kind = "tenant";
            name = "cobalt-clients-vpn";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "icmp";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-mgmt-to-tang-icmp";
          priority = 84;
          from = {
            kind = "tenant";
            name = "cobalt-mgmt";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "icmp";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-to-tang-traceroute";
          priority = 83;
          from = {
            kind = "tenant";
            name = "cobalt-clients";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "traceroute";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-svc-to-tang-traceroute";
          priority = 83;
          from = {
            kind = "tenant";
            name = "cobalt-svc";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "traceroute";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-to-tang-traceroute";
          priority = 83;
          from = {
            kind = "tenant";
            name = "cobalt-iot";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "traceroute";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-iot-srv-to-tang-traceroute";
          priority = 83;
          from = {
            kind = "tenant";
            name = "cobalt-iot-srv";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "traceroute";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-dmz-to-tang-traceroute";
          priority = 83;
          from = {
            kind = "tenant";
            name = "cobalt-dmz";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "traceroute";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-clients-vpn-to-tang-traceroute";
          priority = 83;
          from = {
            kind = "tenant";
            name = "cobalt-clients-vpn";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "traceroute";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-mgmt-to-tang-traceroute";
          priority = 83;
          from = {
            kind = "tenant";
            name = "cobalt-mgmt";
          };
          to = {
            kind = "tenant";
            name = "cobalt-unlock";
          };
          trafficType = "traceroute";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-mgmt-to-mgmt-dns";
          priority = 88;
          from = {
            kind = "tenant";
            name = "cobalt-mgmt";
          };
          to = {
            kind = "service";
            name = "mgmt-dns";
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
        {
          id = "allow-mgmt-dns-to-wan";
          priority = 95;
          from = {
            kind = "service";
            name = "mgmt-dns";
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
        (allowTenantToWan "cobalt-clients" 100)
        (allowTenantToWan "cobalt-svc" 110)
        (allowTenantToWan "cobalt-iot" 120)
        (allowTenantToWan "cobalt-iot-srv" 130)
        (allowTenantToWan "cobalt-mgmt" 140)
        {
          id = "allow-clients-vpn-to-onyx";
          priority = 85;
          from = {
            kind = "tenant";
            name = "cobalt-clients-vpn";
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
      tenant-cobalt-svc = "cobalt-svc";
      tenant-cobalt-clients = "cobalt-clients";
      tenant-cobalt-iot = "cobalt-iot";
      tenant-cobalt-iot-srv = "cobalt-iot-srv";
      tenant-cobalt-dmz = "cobalt-dmz";
      tenant-cobalt-clients-vpn = "cobalt-clients-vpn";
      tenant-cobalt-unlock = "cobalt-unlock";
      tenant-cobalt-mgmt = "cobalt-mgmt";
      external-wan = "wan";
      service-svc-dns = "svc-dns";
      service-clients-dns = "clients-dns";
      service-clients-vpn-dns = "clients-vpn-dns";
      service-iot-dns = "iot-dns";
      service-iot-srv-dns = "iot-srv-dns";
      service-dmz-dns = "dmz-dns";
      service-tang = "tang";
      service-mgmt-dns = "mgmt-dns";
      service-unlock-dns = "unlock-dns";
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
            name = "cobalt-clients-vpn";
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
            name = "cobalt-clients";
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
          id = "allow-mgmt-to-core-dns";
          priority = 89;
          from = {
            kind = "tenant";
            name = "cobalt-mgmt";
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
          id = "allow-mgmt-dns-to-core-dns";
          priority = 90;
          from = {
            kind = "service";
            name = "mgmt-dns";
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
            name = "mgmt-dns";
          };
          advertisedResolver = {
            kind = "service";
            name = "mgmt-dns";
          };
          resolverSource = "local-recursive";
          upstreamResolver = {
            kind = "service";
            name = "core-dns";
            node = "core";
          };
          resolverPath = [
            "access-mgmt"
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

    localDnsSharingIntent = [
      {
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
          source = "cobalt-clients";
          target = "dmz-dns";
          localData = true;
          recursion = false;
          transitiveEgress = false;
          action = "refuse_non_local";
        };
      }
      {
        namespace = "home.arpa.";
        authority = {
          service = "unlock-dns";
          records = [
            "unlock-static-local-data"
          ];
        };
        requester = {
          service = "clients-dns";
          allowedNamespaces = [
            "unlock.home.arpa."
            "90.2.10.in-addr.arpa."
          ];
          recursion = false;
          publicFallback = false;
        };
        relation = {
          id = "allow-clients-dns-to-unlock-dns";
          from = {
            kind = "service";
            name = "clients-dns";
          };
          to = {
            kind = "service";
            name = "unlock-dns";
          };
          trafficType = "dns";
          returnBehavior = "symmetric";
          resolverPath = [
            "access-clients"
            "downstream-selector"
            "access-unlock"
          ];
        };
        providerPolicy = {
          source = "clients-dns";
          action = "refuse_non_local";
        };
        lateralPolicy = {
          source = "cobalt-unlock";
          target = "clients-dns";
          localData = true;
          recursion = false;
          transitiveEgress = false;
          action = "refuse_non_local";
        };
      }
    ];

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
              name = "cobalt-iot-srv";
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
              name = "cobalt-svc";
            }
          ];
        };

        access-clients = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "cobalt-clients";
            }
          ];
        };

        access-iot = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "cobalt-iot";
            }
          ];
        };

        access-iot-srv = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "cobalt-iot-srv";
            }
          ];
        };

        access-dmz = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "cobalt-dmz";
            }
          ];
        };

        access-clients-vpn = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "cobalt-clients-vpn";
            }
          ];
        };

        access-unlock = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "cobalt-unlock";
            }
          ];
        };

        access-mgmt = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "cobalt-mgmt";
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
        [
          "downstream-selector"
          "access-unlock"
        ]
        [
          "downstream-selector"
          "access-mgmt"
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
            name = "cobalt-iot-srv";
          };
        }
      ];
    };
  };
}
