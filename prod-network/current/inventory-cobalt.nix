let
  prodHost = "s-router-cobalt-prod";
  dnsRuntime = import ./dns-runtime-addresses-cobalt.nix;
  nodeName = shortName: "esp0xdeadbeef-cobalt-${shortName}";

  logicalNode = name: {
    enterprise = "esp0xdeadbeef";
    site = "cobalt";
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
    ,
    }:
    {
      inherit logicalInterface;
      attach = bridgeAttach bridge;
      interface = {
        name = interfaceName;
        inherit addr4;
      }
      // (if addr6 == null then { } else { inherit addr6; });
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
        dst = "10.2.3.1";
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

  coreUpstreamLink = "p2p-core-upstream-selector";
  upstreamPolicyVlan2Link = "p2p-policy-upstream-selector--access-access-vlan2--uplink-wan";
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

  core =
    (mkNode "core" {
      upstream-selector = p2pPort {
        link = coreUpstreamLink;
        adapterName = "cb-core-us";
        bridge = "rt-core-upstream-selector";
        interfaceName = "ens3";
      };

      wan = uplinkPort {
        uplink = "wan";
        bridge = "br-wan";
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
      };
    };

  upstreamSelector = mkNode "upstream-selector" {
    core = p2pPort {
      link = coreUpstreamLink;
      adapterName = "cb-us-core";
      bridge = "rt-core-upstream-selector";
      interfaceName = "core";
    };

    policy-vlan2 = p2pPort {
      link = upstreamPolicyVlan2Link;
      adapterName = "cb-us-p2";
      bridge = "rt-upstream-policy-vlan2";
      interfaceName = "policy-vlan2";
    };

    policy-vlan7 = p2pPort {
      link = upstreamPolicyVlan7Link;
      adapterName = "cb-us-p7";
      bridge = "rt-upstream-policy-vlan7";
      interfaceName = "policy";
    };

    policy-vlan8 = p2pPort {
      link = upstreamPolicyVlan8Link;
      adapterName = "cb-us-p8";
      bridge = "rt-upstream-policy-vlan8";
      interfaceName = "policy-vlan8";
    };
  };

  policy = mkNode "policy" {
    upstream-vlan2 = p2pPort {
      link = upstreamPolicyVlan2Link;
      adapterName = "cb-p-us2";
      bridge = "rt-upstream-policy-vlan2";
      interfaceName = "upstream-vlan2";
    };

    upstream-vlan7 = p2pPort {
      link = upstreamPolicyVlan7Link;
      adapterName = "cb-p-us7";
      bridge = "rt-upstream-policy-vlan7";
      interfaceName = "upstream-vlan7";
    };

    upstream-vlan8 = p2pPort {
      link = upstreamPolicyVlan8Link;
      adapterName = "cb-p-us8";
      bridge = "rt-upstream-policy-vlan8";
      interfaceName = "upstream-vlan8";
    };

    downstream-vlan2 = p2pPort {
      link = policyDownstreamVlan2Link;
      adapterName = "cb-p-ds2";
      bridge = "rt-policy-downstream-vlan2";
      interfaceName = "downstream-vlan2";
    };

    downstream-vlan3 = p2pPort {
      link = policyDownstreamVlan3Link;
      adapterName = "cb-p-ds3";
      bridge = "rt-policy-downstream-vlan3";
      interfaceName = "downstream-vlan3";
    };

    downstream-vlan7 = p2pPort {
      link = policyDownstreamVlan7Link;
      adapterName = "cb-p-ds7";
      bridge = "rt-policy-downstream-vlan7";
      interfaceName = "downstr-vlan7";
    };

    downstream-vlan8 = p2pPort {
      link = policyDownstreamVlan8Link;
      adapterName = "cb-p-ds8";
      bridge = "rt-policy-downstream-vlan8";
      interfaceName = "downstr-vlan8";
    };
  };

  downstreamSelector = mkNode "downstream-selector" {
    policy-vlan2 = p2pPort {
      link = policyDownstreamVlan2Link;
      adapterName = "cb-ds-p2";
      bridge = "rt-policy-downstream-vlan2";
      interfaceName = "policy-vlan2";
    };

    policy-vlan3 = p2pPort {
      link = policyDownstreamVlan3Link;
      adapterName = "cb-ds-p3";
      bridge = "rt-policy-downstream-vlan3";
      interfaceName = "policy-vlan3";
    };

    policy-vlan7 = p2pPort {
      link = policyDownstreamVlan7Link;
      adapterName = "cb-ds-p7";
      bridge = "rt-policy-downstream-vlan7";
      interfaceName = "policy-vlan7";
    };

    policy-vlan8 = p2pPort {
      link = policyDownstreamVlan8Link;
      adapterName = "cb-ds-p8";
      bridge = "rt-policy-downstream-vlan8";
      interfaceName = "policy-vlan8";
    };

    access-vlan2 = p2pPort {
      link = downstreamAccessVlan2Link;
      adapterName = "cb-ds-a2";
      bridge = "rt-downstream-access-vlan2";
      interfaceName = "access-vlan2";
    };

    access-vlan3 = p2pPort {
      link = downstreamAccessVlan3Link;
      adapterName = "cb-ds-a3";
      bridge = "rt-downstream-access-vlan3";
      interfaceName = "access-vlan3";
    };

    access-vlan7 = p2pPort {
      link = downstreamAccessVlan7Link;
      adapterName = "cb-ds-a7";
      bridge = "rt-downstream-access-vlan7";
      interfaceName = "access-vlan7";
    };

    access-vlan8 = p2pPort {
      link = downstreamAccessVlan8Link;
      adapterName = "cb-ds-a8";
      bridge = "rt-downstream-access-vlan8";
      interfaceName = "access-vlan8";
    };
  };

  accessVlan2 =
    (mkNode "access-vlan2" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessVlan2Link;
        adapterName = "cb-a2-ds";
        bridge = "rt-downstream-access-vlan2";
        interfaceName = "access-vlan2";
      };

      tenant-vlan2 = tenantPort {
        logicalInterface = "tenant-vlan2";
        bridge = "lan2";
        interfaceName = "lan2";
        addr4 = "10.2.2.1/24";
        addr6 = "fd42:dead:beef:c2::1/64";
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
        };
      };

      advertisements = {
        dhcp4 = {
          tenant-vlan2 = dhcp4Advertisement {
            tenant = "vlan2";
            interface = "tenant-vlan2";
            subnet = "10.2.2.0/24";
            poolStart = "10.2.2.100";
            poolEnd = "10.2.2.200";
            router = "10.2.2.1";
            leaseStatePath = "/var/lib/kea/vlan2.leases";
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
        adapterName = "cb-a3-ds";
        bridge = "rt-downstream-access-vlan3";
        interfaceName = "access-vlan3";
      };

      tenant-vlan3 = tenantPort {
        logicalInterface = "tenant-vlan3";
        bridge = "lan3";
        interfaceName = "lan3";
        addr4 = "10.2.3.1/24";
        addr6 = "fd42:dead:beef:c3::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns = localDns [
          dnsRuntime.requesters.access-vlan3.ipv4
          dnsRuntime.requesters.access-vlan3.ipv6
        ] [ ];
      };

      advertisements = {
        dhcp4 = {
          tenant-vlan3 = dhcp4Advertisement {
            tenant = "vlan3";
            interface = "tenant-vlan3";
            subnet = "10.2.3.0/24";
            poolStart = "10.2.3.100";
            poolEnd = "10.2.3.200";
            router = "10.2.3.1";
            leaseStatePath = "/var/lib/kea/vlan3.leases";
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
        adapterName = "cb-a7-ds";
        bridge = "rt-downstream-access-vlan7";
        interfaceName = "access-vlan7";
      };

      tenant-vlan7 = tenantPort {
        logicalInterface = "tenant-vlan7";
        bridge = "lan7";
        interfaceName = "lan7";
        addr4 = "10.2.7.1/24";
        addr6 = "fd42:dead:beef:c7::1/64";
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
            subnet = "10.2.7.0/24";
            poolStart = "10.2.7.100";
            poolEnd = "10.2.7.200";
            router = "10.2.7.1";
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
        adapterName = "cb-a8-ds";
        bridge = "rt-downstream-access-vlan8";
        interfaceName = "access-vlan8";
      };

      tenant-vlan8 = tenantPort {
        logicalInterface = "tenant-vlan8";
        bridge = "lan8";
        interfaceName = "lan8";
        addr4 = "10.2.8.1/24";
        addr6 = "fd42:dead:beef:c8::1/64";
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
            subnet = "10.2.8.0/24";
            poolStart = "10.2.8.100";
            poolEnd = "10.2.8.200";
            router = "10.2.8.1";
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
    cobalt-core-dns = {
      ipv4 = [ dnsRuntime.resolver.ipv4 ];
      ipv6 = [ dnsRuntime.resolver.ipv6 ];
    };

    cobalt-vlan2-dns = {
      ipv4 = [ dnsRuntime.requesters.access-vlan2.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-vlan2.ipv6 ];
    };

    cobalt-vlan3-dns = {
      ipv4 = [ dnsRuntime.requesters.access-vlan3.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-vlan3.ipv6 ];
    };

    cobalt-vlan7-dns = {
      ipv4 = [ dnsRuntime.requesters.access-vlan7.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-vlan7.ipv6 ];
    };

    cobalt-vlan8-dns = {
      ipv4 = [ dnsRuntime.requesters.access-vlan8.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-vlan8.ipv6 ];
    };
  };

  deployment = {
    hosts = {
      ${prodHost} = {
        wanUplink = "upstream-core";

        uplinks = {
          upstream-core = {
            mode = "vlan";
            vlan = 300;
            parent = "eth1";
            bridge = "br-wan";
            ipv4 = {
              enable = true;
              dhcp = true;
              method = "dhcp";
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
          rt-upstream-policy-vlan7 = { };
          rt-downstream-access-vlan8 = { };
          rt-policy-downstream-vlan8 = { };
          rt-upstream-policy-vlan8 = { };
        };
      };
    };
  };

  realization = {
    nodes = {
      ${nodeName "core"} = core;
      ${nodeName "upstream-selector"} = upstreamSelector;
      ${nodeName "policy"} = policy;
      ${nodeName "downstream-selector"} = downstreamSelector;
      ${nodeName "access-vlan2"} = accessVlan2;
      ${nodeName "access-vlan3"} = accessVlan3;
      ${nodeName "access-vlan7"} = accessVlan7;
      ${nodeName "access-vlan8"} = accessVlan8;
    };
  };
}
