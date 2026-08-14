let
  prodHost = "s-router-prod";
  externalIspHost = "external-isp";
  dnsRuntime = import ./dns-runtime-addresses.nix;
  nodeName = shortName: "esp0xdeadbeef-site-a-${shortName}";

  logicalNode = name: {
    enterprise = "esp0xdeadbeef";
    site = "site-a";
    inherit name;
  };

  bridgeAttach = bridge: {
    kind = "bridge";
    inherit bridge;
  };

  p2pPort =
    { link
    , adapterName
    , bridge
    , interfaceName
    ,
    }:
    {
      inherit link adapterName;
      attach = bridgeAttach bridge;
      interface = {
        name = interfaceName;
      };
    };

  uplinkPort =
    { uplink
    , bridge
    , interfaceName
    ,
    }:
    {
      external = true;
      inherit uplink;
      attach = bridgeAttach bridge;
      interface = {
        name = interfaceName;
      };
    };

  tenantPort =
    { logicalInterface
    , bridge
    , interfaceName
    , addr4
    , addr6 ? null
    , ipv6Ra ? null
    ,
    }:
    {
      inherit logicalInterface;
      attach = bridgeAttach bridge;
      interface = {
        name = interfaceName;
        inherit addr4;
      }
      // (if addr6 == null then { } else { inherit addr6; })
      // (if ipv6Ra == null then { } else { inherit ipv6Ra; });
    };

  mkNode =
    name: ports:
    {
      host = prodHost;
      platform = "nixos-container";
      logicalNode = logicalNode name;
      inherit ports;
    };

  persistentDhcpState = {
    persistence = {
      required = true;
      root = "/var/lib/kea";
      durabilityClass = "restart-persistent";
      stateLossHandling = "fail-closed-require-persistent-state";
    };
  };

  accessDns =
    { addresses
    , localRecords ? [ ]
    ,
    }:
    {
      # TEMPORARY FS-540 SMS projection: the target intent is address-free, but
      # the pinned compiler cannot consume its service-to-service relation
      # without changing unrelated route materialization. Keep the core service
      # endpoint explicit here until that SMS row is fixed upstream.
      forwarders = [
        dnsRuntime.resolver.ipv4
        dnsRuntime.resolver.ipv6
      ];
      outgoingInterfaces = addresses;
      roles.recursion.outgoingInterfaces = addresses;
      inherit localRecords;
    };

  localDns = addresses: records: {
    forwarders = [ ];
    outgoingInterfaces = addresses;
    roles.recursion.outgoingInterfaces = addresses;
    localZones = [
      {
        name = "lan.";
        type = "static";
      }
    ];
    localRecords = records;
    upstreamResolvers = [
      {
        dst = "192.168.3.1";
        scope = "local-access";
        source = "router-self";
      }
    ];
  };

  dhcp4Advertisement =
    { tenant
    , interface
    , subnet
    , poolStart
    , poolEnd
    , router
    , leaseStatePath
    , reservationSource ? null
    ,
    }:
    {
      inherit interface;
      id = tenant;
      inherit subnet;
      pool = {
        start = poolStart;
        end = poolEnd;
      };
      inherit router;
      dnsServers = [ router ];
      domain = "lan.";
      leaseState.path = leaseStatePath;
    }
    // (if reservationSource == null then { } else { inherit reservationSource; });

  protectedReservationSource = sourceFile: {
    schema = "gamp-protected-reservation-set-v1";
    sourceClass = "protected";
    inherit sourceFile;
  };

  slaacRa = interface: {
    enabled = true;
    inherit interface;
    rdnss = [ "router-self" ];
    dnssl = [ "lan." ];
    managed = false;
    otherConfig = false;
    onLink = true;
    autonomous = true;
  };

  pppoeCredentials = {
    usernameFile = "/run/secrets/pppoe-username";
    passwordFile = "/run/secrets/pppoe-password";
  };

  coreUpstreamLink = "p2p-core-upstream-selector";
  upstreamPolicyVlan2Link = "p2p-policy-upstream-selector--access-access-vlan2--uplink-wan";
  upstreamPolicyVlan3Link = "p2p-policy-upstream-selector--access-access-vlan3--uplink-wan";
  upstreamPolicyVlan7Link = "p2p-policy-upstream-selector--access-access-vlan7--uplink-wan";
  policyDownstreamVlan2Link = "p2p-downstream-selector-policy--access-access-vlan2";
  policyDownstreamVlan3Link = "p2p-downstream-selector-policy--access-access-vlan3";
  policyDownstreamVlan7Link = "p2p-downstream-selector-policy--access-access-vlan7";
  downstreamAccessVlan2Link = "p2p-access-vlan2-downstream-selector";
  downstreamAccessVlan3Link = "p2p-access-vlan3-downstream-selector";
  downstreamAccessVlan7Link = "p2p-access-vlan7-downstream-selector";
  upstreamPolicyVlan8Link = "p2p-policy-upstream-selector--access-access-vlan8--uplink-wan";
  policyDownstreamVlan8Link = "p2p-downstream-selector-policy--access-access-vlan8";
  downstreamAccessVlan8Link = "p2p-access-vlan8-downstream-selector";
  sNebulaContainerAddress = "192.168.3.10";
  sNebulaContainerAddress6 = "fd42:dead:beef:3::1337:dead:beef";
  sLlmInferenceContainerAddress = "192.168.3.11";

  core =
    (mkNode "core" {
      upstream-selector = p2pPort {
        link = coreUpstreamLink;
        adapterName = "prod-9dd122d7014e";
        bridge = "rt-core-upstream-selector";
        interfaceName = "ens3";
      };

      wan = uplinkPort {
        uplink = "wan";
        bridge = "br-wan6";
        interfaceName = "wan";
      };
    })
    // {
      services = {
        dns = {
          listen = [
            dnsRuntime.resolver.ipv4
            dnsRuntime.resolver.ipv6
          ];
          allowFrom = [
            dnsRuntime.requesters.access-vlan2.clientIpv4
            dnsRuntime.requesters.access-vlan2.clientIpv6
            "${dnsRuntime.requesters.access-vlan7.ipv4}/32"
            "${dnsRuntime.requesters.access-vlan7.ipv6}/128"
            "${dnsRuntime.requesters.access-vlan8.ipv4}/32"
            "${dnsRuntime.requesters.access-vlan8.ipv6}/128"
          ];
        };

        pppoe = {
          client = {
            interface = "wan";
            runtimeInterface = "ppp0";
            defaultRoute = true;
            usePeerDns = false;
            mtu = 1492;
            credentials = pppoeCredentials;
          };
        };
      };
    };

  ispPppoePeer = {
    host = externalIspHost;
    platform = "linux";
    logicalNode = logicalNode "isp-pppoe-peer";
    ports = { };

    advertisements = {
      dhcp4.wan = {
        enabled = false;
      };

      ipv6Ra.wan = {
        enabled = false;
      };
    };

    services = {
      pppoe = {
        server = {
          interface = "wan";
          implementation = "rp-pppoe";
          providerAddress = "100.64.0.1";
          customerAddress = "100.64.0.2";
          maxSessions = 1;
          mtu = 1492;
          credentials = pppoeCredentials;
        };
      };
    };
  };

  upstreamSelector = mkNode "upstream-selector" {
    core = p2pPort {
      link = coreUpstreamLink;
      adapterName = "prod-381287f8b9a7";
      bridge = "rt-core-upstream-selector";
      interfaceName = "core";
    };

    policy-vlan2 = p2pPort {
      link = upstreamPolicyVlan2Link;
      adapterName = "prod-e239e2d75459";
      bridge = "rt-upstream-policy-vlan2";
      interfaceName = "policy-vlan2";
    };

    policy-vlan3 = p2pPort {
      link = upstreamPolicyVlan3Link;
      adapterName = "prod-5b8cc11484ec";
      bridge = "rt-upstream-policy-vlan3";
      interfaceName = "policy-vlan3";
    };

    policy-vlan7 = p2pPort {
      link = upstreamPolicyVlan7Link;
      adapterName = "prod-f3bcb2fb5b11";
      bridge = "rt-upstream-policy-vlan7";
      interfaceName = "policy";
    };

    policy-vlan8 = p2pPort {
      link = upstreamPolicyVlan8Link;
      adapterName = "prod-8a1d3c2e4f56";
      bridge = "rt-upstream-policy-vlan8";
      interfaceName = "policy-vlan8";
    };
  };

  policy = mkNode "policy" {
    upstream-vlan2 = p2pPort {
      link = upstreamPolicyVlan2Link;
      adapterName = "prod-d9b6a07da75d";
      bridge = "rt-upstream-policy-vlan2";
      interfaceName = "upstream-vlan2";
    };

    upstream-vlan3 = p2pPort {
      link = upstreamPolicyVlan3Link;
      adapterName = "prod-782910d2984a";
      bridge = "rt-upstream-policy-vlan3";
      interfaceName = "upstream-vlan3";
    };

    upstream-vlan7 = p2pPort {
      link = upstreamPolicyVlan7Link;
      adapterName = "prod-e0ca29726ada";
      bridge = "rt-upstream-policy-vlan7";
      interfaceName = "upstream-vlan7";
    };

    upstream-vlan8 = p2pPort {
      link = upstreamPolicyVlan8Link;
      adapterName = "prod-9b2e4d1c3a65";
      bridge = "rt-upstream-policy-vlan8";
      interfaceName = "upstream-vlan8";
    };

    downstream-vlan2 = p2pPort {
      link = policyDownstreamVlan2Link;
      adapterName = "prod-34fc7c237d32";
      bridge = "rt-policy-downstream-vlan2";
      interfaceName = "downstream-vlan2";
    };

    downstream-vlan3 = p2pPort {
      link = policyDownstreamVlan3Link;
      adapterName = "prod-85d312b436f1";
      bridge = "rt-policy-downstream-vlan3";
      interfaceName = "downstream-vlan3";
    };

    downstream-vlan7 = p2pPort {
      link = policyDownstreamVlan7Link;
      adapterName = "prod-750978245400";
      bridge = "rt-policy-downstream-vlan7";
      interfaceName = "downstr-vlan7";
    };

    downstream-vlan8 = p2pPort {
      link = policyDownstreamVlan8Link;
      adapterName = "prod-7c4a1f8e2d39";
      bridge = "rt-policy-downstream-vlan8";
      interfaceName = "downstr-vlan8";
    };
  };

  downstreamSelector = mkNode "downstream-selector" {
    policy-vlan2 = p2pPort {
      link = policyDownstreamVlan2Link;
      adapterName = "prod-14f315fedc1c";
      bridge = "rt-policy-downstream-vlan2";
      interfaceName = "policy-vlan2";
    };

    policy-vlan3 = p2pPort {
      link = policyDownstreamVlan3Link;
      adapterName = "prod-405ce986d1bb";
      bridge = "rt-policy-downstream-vlan3";
      interfaceName = "policy-vlan3";
    };

    policy-vlan7 = p2pPort {
      link = policyDownstreamVlan7Link;
      adapterName = "prod-61b06694fc25";
      bridge = "rt-policy-downstream-vlan7";
      interfaceName = "policy-vlan7";
    };

    policy-vlan8 = p2pPort {
      link = policyDownstreamVlan8Link;
      adapterName = "prod-5d8a1c3e2f47";
      bridge = "rt-policy-downstream-vlan8";
      interfaceName = "policy-vlan8";
    };

    access-vlan2 = p2pPort {
      link = downstreamAccessVlan2Link;
      adapterName = "prod-540264d3608b";
      bridge = "rt-downstream-access-vlan2";
      interfaceName = "access-vlan2";
    };

    access-vlan3 = p2pPort {
      link = downstreamAccessVlan3Link;
      adapterName = "prod-35d943f82599";
      bridge = "rt-downstream-access-vlan3";
      interfaceName = "access-vlan3";
    };

    access-vlan7 = p2pPort {
      link = downstreamAccessVlan7Link;
      adapterName = "prod-22766d6cc0fd";
      bridge = "rt-downstream-access-vlan7";
      interfaceName = "access-vlan7";
    };

    access-vlan8 = p2pPort {
      link = downstreamAccessVlan8Link;
      adapterName = "prod-3e6b2f1d4c58";
      bridge = "rt-downstream-access-vlan8";
      interfaceName = "access-vlan8";
    };
  };

  accessVlan2 =
    (mkNode "access-vlan2" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessVlan2Link;
        adapterName = "prod-977806758561";
        bridge = "rt-downstream-access-vlan2";
        interfaceName = "access-vlan2";
      };

      tenant-vlan2 = tenantPort {
        logicalInterface = "tenant-vlan2";
        bridge = "lan2";
        interfaceName = "lan2";
        addr4 = "192.168.1.1/24";
        addr6 = "fd42:1::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns = accessDns {
          addresses = [
            dnsRuntime.requesters.access-vlan2.ipv4
            dnsRuntime.requesters.access-vlan2.ipv6
          ];
          # VLAN 3 owns the Nebula endpoint and publishes its local DNS data.
          # VLAN 2 reaches that authority through the temporary exact-name
          # forwarding compatibility module instead of duplicating the record.
          localRecords = [ ];
        };
      };

      advertisements = {
        dhcp4 = {
          tenant-vlan2 = dhcp4Advertisement {
            tenant = "vlan2";
            interface = "tenant-vlan2";
            subnet = "192.168.1.0/24";
            poolStart = "192.168.1.100";
            poolEnd = "192.168.1.200";
            router = "192.168.1.1";
            leaseStatePath = "/var/lib/kea/vlan2.leases";
            reservationSource = protectedReservationSource "/run/secrets/s-router-prod-vlan2-reservations.json";
          };
        };

        ipv6Ra = {
          tenant-vlan2 = slaacRa "tenant-vlan2";
        };
      };
    };

  accessVlan3 =
    (mkNode "access-vlan3" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessVlan3Link;
        adapterName = "prod-2097f33d7a15";
        bridge = "rt-downstream-access-vlan3";
        interfaceName = "access-vlan3";
      };

      tenant-vlan3 = tenantPort {
        logicalInterface = "tenant-vlan3";
        bridge = "lan3";
        interfaceName = "lan3";
        addr4 = "192.168.3.1/24";
        addr6 = "fd42:dead:beef:3::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns =
          localDns
            [
              dnsRuntime.requesters.access-vlan3.ipv4
              dnsRuntime.requesters.access-vlan3.ipv6
            ]
            [
              {
                # This is the single authority copy. Do not duplicate it into
                # VLAN 2; network-* must eventually derive this publication
                # from the modeled endpoint itself.
                name = "s-nebula-container.lan.";
                a = [ sNebulaContainerAddress ];
                aaaa = [ sNebulaContainerAddress6 ];
              }
              {
                name = "s-llm-inference-container.lan.";
                a = [ sLlmInferenceContainerAddress ];
              }
            ];
      };

      advertisements = {
        dhcp4 = {
          tenant-vlan3 = dhcp4Advertisement {
            tenant = "vlan3";
            interface = "tenant-vlan3";
            subnet = "192.168.3.0/24";
            poolStart = "192.168.3.100";
            poolEnd = "192.168.3.200";
            router = "192.168.3.1";
            leaseStatePath = "/var/lib/kea/vlan3.leases";
            reservationSource = protectedReservationSource "/run/secrets/s-router-prod-vlan3-reservations.json";
          };
        };

        ipv6Ra = {
          tenant-vlan3 = slaacRa "tenant-vlan3";
        };
      };
    };

  accessVlan7 =
    (mkNode "access-vlan7" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessVlan7Link;
        adapterName = "prod-7af4de3b431e";
        bridge = "rt-downstream-access-vlan7";
        interfaceName = "access-vlan7";
      };

      tenant-vlan7 = tenantPort {
        logicalInterface = "tenant-vlan7";
        bridge = "lan7";
        interfaceName = "lan7";
        addr4 = "192.168.2.1/24";
        addr6 = "fd42:dead:beef:7::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns = accessDns {
          addresses = [
            dnsRuntime.requesters.access-vlan7.ipv4
            dnsRuntime.requesters.access-vlan7.ipv6
          ];
        };
      };

      advertisements = {
        dhcp4 = {
          tenant-vlan7 = dhcp4Advertisement {
            tenant = "vlan7";
            interface = "tenant-vlan7";
            subnet = "192.168.2.0/24";
            poolStart = "192.168.2.100";
            poolEnd = "192.168.2.200";
            router = "192.168.2.1";
            leaseStatePath = "/var/lib/kea/vlan7.leases";
          };
        };

        ipv6Ra = {
          tenant-vlan7 = slaacRa "tenant-vlan7";
        };
      };
    };

  accessVlan8 =
    (mkNode "access-vlan8" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessVlan8Link;
        adapterName = "prod-8b7c6d5e4f39";
        bridge = "rt-downstream-access-vlan8";
        interfaceName = "access-vlan8";
      };

      tenant-vlan8 = tenantPort {
        logicalInterface = "tenant-vlan8";
        bridge = "lan8";
        interfaceName = "lan8";
        addr4 = "192.168.8.1/24";
        addr6 = "fd42:dead:beef:8::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns = accessDns {
          addresses = [
            dnsRuntime.requesters.access-vlan8.ipv4
            dnsRuntime.requesters.access-vlan8.ipv6
          ];
        };
      };

      advertisements = {
        dhcp4 = {
          tenant-vlan8 = dhcp4Advertisement {
            tenant = "vlan8";
            interface = "tenant-vlan8";
            subnet = "192.168.8.0/24";
            poolStart = "192.168.8.100";
            poolEnd = "192.168.8.200";
            router = "192.168.8.1";
            leaseStatePath = "/var/lib/kea/vlan8.leases";
          };
        };

        ipv6Ra = {
          tenant-vlan8 = slaacRa "tenant-vlan8";
        };
      };
    };
in
{
  schemaVersion = 1;

  endpoints = {
    core-dns = {
      ipv4 = [ dnsRuntime.resolver.ipv4 ];
      ipv6 = [ dnsRuntime.resolver.ipv6 ];
    };

    vlan2-dns = {
      ipv4 = [ dnsRuntime.requesters.access-vlan2.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-vlan2.ipv6 ];
    };

    vlan3-dns = {
      ipv4 = [ dnsRuntime.requesters.access-vlan3.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-vlan3.ipv6 ];
    };

    s-nebula-container = {
      ipv4 = [ sNebulaContainerAddress ];
      ipv6 = [ sNebulaContainerAddress6 ];
    };

    s-llm-inference-container = {
      ipv4 = [ sLlmInferenceContainerAddress ];
    };

    vlan7-dns = {
      ipv4 = [ dnsRuntime.requesters.access-vlan7.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-vlan7.ipv6 ];
    };

    vlan8-dns = {
      ipv4 = [ dnsRuntime.requesters.access-vlan8.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-vlan8.ipv6 ];
    };
  };

  deployment = {
    hosts = {
      ${externalIspHost} = { };

      ${prodHost} = {
        wanUplink = "upstream-core";

        uplinks = {
          upstream-core = {
            parent = "eth1";
            mode = "pppoe";
            vlan = 6;
            bridge = "br-wan6";

            ipv4 = {
              method = "pppoe";
            };

            ipv6 = {
              method = "pppoe";
            };

            pppoe = {
              interface = "ppp0";
              usernameSecret = "/run/secrets/pppoe-username";
              passwordSecret = "/run/secrets/pppoe-password";
            };
          };

          trunk = {
            parent = "eth0";
            bridge = "br-lan-trunk";
            mode = "trunk";
          };
        };

        transitBridges = {
          lan2 = {
            name = "lan2";
            vlan = 2;
            parentUplink = "trunk";
          };

          lan3 = {
            name = "lan3";
            vlan = 3;
            parentUplink = "trunk";
          };

          lan7 = {
            name = "lan7";
            vlan = 7;
            parentUplink = "trunk";
          };

          lan8 = {
            name = "lan8";
            vlan = 8;
            parentUplink = "trunk";
          };
        };

        bridgeNetworks = {
          rt-core-upstream-selector = { };
          rt-downstream-access-vlan2 = { };
          rt-downstream-access-vlan3 = { };
          rt-downstream-access-vlan7 = { };
          rt-policy-downstream-vlan2 = { };
          rt-policy-downstream-vlan3 = { };
          rt-policy-downstream-vlan7 = { };
          rt-upstream-policy-vlan2 = { };
          rt-upstream-policy-vlan3 = { };
          rt-upstream-policy-vlan7 = { };
          rt-downstream-access-vlan8 = { };
          rt-policy-downstream-vlan8 = { };
          rt-upstream-policy-vlan8 = { };
        };
      };
    };
  };

  realization = {
    fabricLinks = {
      "${nodeName "downstream-selector"}" = builtins.mapAttrs
        (_: port: {
          kind = "selector-fabric-link";
          link = port.link;
          transport.hostFacing = false;
        })
        downstreamSelector.ports;

      "${nodeName "upstream-selector"}" = builtins.mapAttrs
        (_: port: {
          kind = "selector-fabric-link";
          link = port.link;
          transport.hostFacing = false;
        })
        upstreamSelector.ports;
    };

    nodes = {
      ${nodeName "core"} = core;
      ${nodeName "isp-pppoe-peer"} = ispPppoePeer;
      ${nodeName "upstream-selector"} = upstreamSelector // { ports = { }; };
      ${nodeName "policy"} = policy;
      ${nodeName "downstream-selector"} = downstreamSelector // { ports = { }; };
      ${nodeName "access-vlan2"} = accessVlan2;
      ${nodeName "access-vlan3"} = accessVlan3;
      ${nodeName "access-vlan7"} = accessVlan7;
      ${nodeName "access-vlan8"} = accessVlan8;
    };
  };

  render = {
    hosts = {
      core = {
        containerTemplate = "wan";
        deploymentHost = prodHost;
        runtimeRole = "core";
        wanUplink = "upstream-core";
      };

      upstream-selector = {
        deploymentHost = prodHost;
      };

      policy = {
        deploymentHost = prodHost;
      };

      downstream-selector = {
        deploymentHost = prodHost;
      };

      access-vlan2 = {
        deploymentHost = prodHost;
      };

      access-vlan3 = {
        deploymentHost = prodHost;
      };

      access-vlan7 = {
        deploymentHost = prodHost;
      };

      access-vlan8 = {
        deploymentHost = prodHost;
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
  };
}
