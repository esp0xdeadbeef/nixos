let
  prodHost = "s-router-prod";
  externalIspHost = "external-isp";
  dnsRuntime = import ./dns-runtime-addresses.nix;
  nodeName = shortName: "esp0xdeadbeef-neon-${shortName}";

  logicalNode = name: {
    enterprise = "esp0xdeadbeef";
    site = "neon";
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

  dmzLocalDns = addresses: records: {
    forwarders = [ ];
    outgoingInterfaces = addresses;
    roles.recursion.outgoingInterfaces = addresses;
    localZones = [
      {
        name = "dmz.home.arpa.";
        type = "static";
      }
    ];
    localRecords = records;
    upstreamResolvers = [
      {
        dst = "10.3.60.1";
        scope = "local-access";
        source = "router-self";
      }
    ];
  };

  unlockDns = addresses: {
    forwarders = [ ];
    outgoingInterfaces = addresses;
    roles.recursion.outgoingInterfaces = addresses;
    localZones = [
      {
        name = "unlock.home.arpa.";
        type = "static";
      }
    ];
    localRecords = [
      {
        name = "tang.unlock.home.arpa.";
        a = [ "10.3.90.10" ];
        aaaa = [ "fd42:dead:beef:390::10" ];
      }
    ];
  };

  protectedReservationSource = sourceFile: {
    schema = "gamp-protected-reservation-set-v1";
    sourceClass = "protected";
    inherit sourceFile;
  };

  neonReservations = import ./neon-reservations.nix;

  reservationsFor = vlan:
    builtins.map
      (deviceId:
        let
          device = neonReservations.${deviceId};
        in
        {
          id = deviceId;
          ipv4 = {
            hostOffset = device.scopes.${vlan};
          };
          macSource = {
            accepted = true;
            purpose = "static-dhcp-reservation";
            sourceClass = "protected";
            source = "protected-inventory";
            secretRef = deviceId;
          };
        }
        // (if device ? hostname && device.hostname != null then { hostname = device.hostname; } else { }))
      (builtins.filter
        (deviceId: neonReservations.${deviceId}.scopes ? ${vlan})
        (builtins.attrNames neonReservations));

  dhcp4Advertisement =
    { tenant
    , interface
    , subnet
    , poolStart
    , poolEnd
    , router
    , leaseStatePath
    , domain ? "lan."
    , reservationSource ? null
    , reservations ? null
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
      inherit domain;
      leaseState.path = leaseStatePath;
    }
    // (if reservationSource == null then { } else { inherit reservationSource; })
    // (if reservations == null then { } else { inherit reservations; });

  slaacRa = interface:
    let
      tenant = builtins.substring 7 (builtins.stringLength interface - 7) interface;
      plane =
        if builtins.substring 0 7 tenant == "cobalt-" then
          builtins.substring 7 (builtins.stringLength tenant - 7) tenant
        else if builtins.substring 0 5 tenant == "neon-" then
          builtins.substring 5 (builtins.stringLength tenant - 5) tenant
        else
          tenant;
    in
    {
      enabled = true;
      inherit interface;
      rdnss = [ "router-self" ];
      dnssl = [ "${plane}.home.arpa." ];
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
  upstreamPolicySvcLink = "p2p-policy-upstream-selector--access-access-svc--uplink-wan";
  upstreamPolicyClientsLink = "p2p-policy-upstream-selector--access-access-clients--uplink-wan";
  upstreamPolicyIotSrvLink = "p2p-policy-upstream-selector--access-access-iot-srv--uplink-wan";
  upstreamPolicyIotLink = "p2p-policy-upstream-selector--access-access-iot--uplink-wan";
  upstreamPolicyMgmtLink = "p2p-policy-upstream-selector--access-access-mgmt--uplink-wan";
  policyDownstreamSvcLink = "p2p-downstream-selector-policy--access-access-svc";
  policyDownstreamClientsLink = "p2p-downstream-selector-policy--access-access-clients";
  policyDownstreamDmzLink = "p2p-downstream-selector-policy--access-access-dmz";
  policyDownstreamIotSrvLink = "p2p-downstream-selector-policy--access-access-iot-srv";
  policyDownstreamIotLink = "p2p-downstream-selector-policy--access-access-iot";
  policyDownstreamUnlockLink = "p2p-downstream-selector-policy--access-access-unlock";
  policyDownstreamMgmtLink = "p2p-downstream-selector-policy--access-access-mgmt";
  downstreamAccessSvcLink = "p2p-access-svc-downstream-selector";
  downstreamAccessClientsLink = "p2p-access-clients-downstream-selector";
  downstreamAccessDmzLink = "p2p-access-dmz-downstream-selector";
  downstreamAccessIotSrvLink = "p2p-access-iot-srv-downstream-selector";
  downstreamAccessIotLink = "p2p-access-iot-downstream-selector";
  downstreamAccessUnlockLink = "p2p-access-unlock-downstream-selector";
  downstreamAccessMgmtLink = "p2p-access-mgmt-downstream-selector";
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
            dnsRuntime.requesters.access-clients.clientIpv4
            dnsRuntime.requesters.access-clients.clientIpv6
            dnsRuntime.requesters.access-svc.clientIpv4
            dnsRuntime.requesters.access-svc.clientIpv6
            "${dnsRuntime.requesters.access-iot-srv.ipv4}/32"
            "${dnsRuntime.requesters.access-iot-srv.ipv6}/128"
            "${dnsRuntime.requesters.access-iot.ipv4}/32"
            "${dnsRuntime.requesters.access-iot.ipv6}/128"
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
    policy-svc = p2pPort {
      link = upstreamPolicySvcLink;
      adapterName = "prod-us-svc";
      bridge = "rt-upstream-policy-svc";
      interfaceName = "policy-svc";
    };

    policy-clients = p2pPort {
      link = upstreamPolicyClientsLink;
      adapterName = "prod-us-clients";
      bridge = "rt-upstream-policy-clients";
      interfaceName = "policy-clients";
    };

    policy-iot-srv = p2pPort {
      link = upstreamPolicyIotSrvLink;
      adapterName = "prod-us-iot-srv";
      bridge = "rt-upstream-policy-iot-srv";
      interfaceName = "policy-iot-srv";
    };

    policy-iot = p2pPort {
      link = upstreamPolicyIotLink;
      adapterName = "prod-us-iot";
      bridge = "rt-upstream-policy-iot";
      interfaceName = "policy-iot";
    };

    policy-mgmt = p2pPort {
      link = upstreamPolicyMgmtLink;
      adapterName = "prod-us-mgmt";
      bridge = "rt-upstream-policy-mgmt";
      interfaceName = "policy-mgmt";
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
    upstream-svc = p2pPort {
      link = upstreamPolicySvcLink;
      adapterName = "prod-p-us-svc";
      bridge = "rt-upstream-policy-svc";
      interfaceName = "upstream-svc";
    };

    upstream-clients = p2pPort {
      link = upstreamPolicyClientsLink;
      adapterName = "prod-p-us-clients";
      bridge = "rt-upstream-policy-clients";
      interfaceName = "upstream-clients";
    };

    upstream-iot-srv = p2pPort {
      link = upstreamPolicyIotSrvLink;
      adapterName = "prod-p-us-iot-srv";
      bridge = "rt-upstream-policy-iot-srv";
      interfaceName = "upstream-iot-srv";
    };

    upstream-iot = p2pPort {
      link = upstreamPolicyIotLink;
      adapterName = "prod-p-us-iot";
      bridge = "rt-upstream-policy-iot";
      interfaceName = "upstream-iot";
    };

    upstream-mgmt = p2pPort {
      link = upstreamPolicyMgmtLink;
      adapterName = "prod-p-us-mgmt";
      bridge = "rt-upstream-policy-mgmt";
      interfaceName = "upstream-mgmt";
    };

    downstream-svc = p2pPort {
      link = policyDownstreamSvcLink;
      adapterName = "prod-p-ds-svc";
      bridge = "rt-policy-downstream-svc";
      interfaceName = "downstream-svc";
    };

    downstream-clients = p2pPort {
      link = policyDownstreamClientsLink;
      adapterName = "prod-p-ds-clients";
      bridge = "rt-policy-downstream-clients";
      interfaceName = "downstream-clients";
    };

    downstream-dmz = p2pPort {
      link = policyDownstreamDmzLink;
      adapterName = "prod-p-ds-dmz";
      bridge = "rt-policy-downstream-dmz";
      interfaceName = "downstream-dmz";
    };

    downstream-iot-srv = p2pPort {
      link = policyDownstreamIotSrvLink;
      adapterName = "prod-p-ds-iot-srv";
      bridge = "rt-policy-downstream-iot-srv";
      interfaceName = "downstr-iot-srv";
    };

    downstream-iot = p2pPort {
      link = policyDownstreamIotLink;
      adapterName = "prod-p-ds-iot";
      bridge = "rt-policy-downstream-iot";
      interfaceName = "downstr-iot";
    };

    downstream-unlock = p2pPort {
      link = policyDownstreamUnlockLink;
      adapterName = "prod-p-ds-unlock";
      bridge = "rt-policy-downstream-unlock";
      interfaceName = "downstream-unlock";
    };

    downstream-mgmt = p2pPort {
      link = policyDownstreamMgmtLink;
      adapterName = "prod-p-ds-mgmt";
      bridge = "rt-policy-downstream-mgmt";
      interfaceName = "downstream-mgmt";
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
    policy-svc = p2pPort {
      link = policyDownstreamSvcLink;
      adapterName = "prod-ds-p-svc";
      bridge = "rt-policy-downstream-svc";
      interfaceName = "policy-svc";
    };

    policy-clients = p2pPort {
      link = policyDownstreamClientsLink;
      adapterName = "prod-ds-p-clients";
      bridge = "rt-policy-downstream-clients";
      interfaceName = "policy-clients";
    };

    policy-dmz = p2pPort {
      link = policyDownstreamDmzLink;
      adapterName = "prod-ds-p-dmz";
      bridge = "rt-policy-downstream-dmz";
      interfaceName = "policy-dmz";
    };

    policy-iot-srv = p2pPort {
      link = policyDownstreamIotSrvLink;
      adapterName = "prod-ds-p-iot-srv";
      bridge = "rt-policy-downstream-iot-srv";
      interfaceName = "policy-iot-srv";
    };

    policy-iot = p2pPort {
      link = policyDownstreamIotLink;
      adapterName = "prod-ds-p-iot";
      bridge = "rt-policy-downstream-iot";
      interfaceName = "policy-iot";
    };

    policy-unlock = p2pPort {
      link = policyDownstreamUnlockLink;
      adapterName = "prod-ds-p-unlock";
      bridge = "rt-policy-downstream-unlock";
      interfaceName = "policy-unlock";
    };

    policy-mgmt = p2pPort {
      link = policyDownstreamMgmtLink;
      adapterName = "prod-ds-p-mgmt";
      bridge = "rt-policy-downstream-mgmt";
      interfaceName = "policy-mgmt";
    };

    access-svc = p2pPort {
      link = downstreamAccessSvcLink;
      adapterName = "prod-ds-a-svc";
      bridge = "rt-downstream-access-svc";
      interfaceName = "access-svc";
    };

    access-clients = p2pPort {
      link = downstreamAccessClientsLink;
      adapterName = "prod-ds-a-clients";
      bridge = "rt-downstream-access-clients";
      interfaceName = "access-clients";
    };

    access-dmz = p2pPort {
      link = downstreamAccessDmzLink;
      adapterName = "prod-ds-a-dmz";
      bridge = "rt-downstream-access-dmz";
      interfaceName = "access-dmz";
    };

    access-iot-srv = p2pPort {
      link = downstreamAccessIotSrvLink;
      adapterName = "prod-ds-a-iot-srv";
      bridge = "rt-downstream-access-iot-srv";
      interfaceName = "access-iot-srv";
    };

    access-iot = p2pPort {
      link = downstreamAccessIotLink;
      adapterName = "prod-ds-a-iot";
      bridge = "rt-downstream-access-iot";
      interfaceName = "access-iot";
    };

    access-unlock = p2pPort {
      link = downstreamAccessUnlockLink;
      adapterName = "prod-ds-a-unlock";
      bridge = "rt-downstream-access-unlock";
      interfaceName = "access-unlock";
    };

    access-mgmt = p2pPort {
      link = downstreamAccessMgmtLink;
      adapterName = "prod-ds-a-mgmt";
      bridge = "rt-downstream-access-mgmt";
      interfaceName = "access-mgmt";
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
            reservations = reservationsFor "vlan2";
            reservationSource = protectedReservationSource "/run/secrets/devices/";
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

  accessClients =
    (mkNode "access-clients" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessClientsLink;
        adapterName = "prod-a-clients-ds";
        bridge = "rt-downstream-access-clients";
        interfaceName = "access-clients";
      };

      tenant-neon-clients = tenantPort {
        logicalInterface = "tenant-neon-clients";
        bridge = "clients";
        interfaceName = "clients";
        addr4 = "10.3.30.1/24";
        addr6 = "fd42:dead:beef:330::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns = accessDns {
          addresses = [
            dnsRuntime.requesters.access-clients.ipv4
            dnsRuntime.requesters.access-clients.ipv6
          ];
        };
      };

      advertisements = {
        dhcp4 = {
          tenant-neon-clients = dhcp4Advertisement {
            tenant = "neon-clients";
            interface = "tenant-neon-clients";
            subnet = "10.3.30.0/24";
            poolStart = "10.3.30.100";
            poolEnd = "10.3.30.200";
            router = "10.3.30.1";
            leaseStatePath = "/var/lib/kea/clients.leases";
            domain = "clients.home.arpa.";
            reservations = reservationsFor "neon-clients";
            reservationSource = protectedReservationSource "/run/secrets/devices/";
          };
        };

        ipv6Ra = {
          tenant-neon-clients = slaacRa "tenant-neon-clients";
        };
      };
    };

  accessSvc =
    (mkNode "access-svc" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessSvcLink;
        adapterName = "prod-a-svc-ds";
        bridge = "rt-downstream-access-svc";
        interfaceName = "access-svc";
      };

      tenant-neon-svc = tenantPort {
        logicalInterface = "tenant-neon-svc";
        bridge = "svc";
        interfaceName = "svc";
        addr4 = "10.3.20.1/24";
        addr6 = "fd42:dead:beef:320::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns = accessDns {
          addresses = [
            dnsRuntime.requesters.access-svc.ipv4
            dnsRuntime.requesters.access-svc.ipv6
          ];
        };
      };

      advertisements = {
        dhcp4 = {
          tenant-neon-svc = dhcp4Advertisement {
            tenant = "neon-svc";
            interface = "tenant-neon-svc";
            subnet = "10.3.20.0/24";
            poolStart = "10.3.20.100";
            poolEnd = "10.3.20.200";
            router = "10.3.20.1";
            leaseStatePath = "/var/lib/kea/svc.leases";
            domain = "svc.home.arpa.";
            reservationSource = protectedReservationSource "/run/secrets/devices/";
          };
        };

        ipv6Ra = {
          tenant-neon-svc = slaacRa "tenant-neon-svc";
        };
      };
    };

  accessDmz =
    (mkNode "access-dmz" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessDmzLink;
        adapterName = "prod-a-dmz-ds";
        bridge = "rt-downstream-access-dmz";
        interfaceName = "access-dmz";
      };

      tenant-neon-dmz = tenantPort {
        logicalInterface = "tenant-neon-dmz";
        bridge = "dmz";
        interfaceName = "dmz";
        addr4 = "10.3.60.1/24";
        addr6 = "fd42:dead:beef:360::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns = dmzLocalDns [
          dnsRuntime.requesters.access-dmz.ipv4
          dnsRuntime.requesters.access-dmz.ipv6
        ] [ ];
      };

      advertisements = {
        dhcp4 = {
          tenant-neon-dmz = dhcp4Advertisement {
            tenant = "neon-dmz";
            interface = "tenant-neon-dmz";
            subnet = "10.3.60.0/24";
            poolStart = "10.3.60.100";
            poolEnd = "10.3.60.200";
            router = "10.3.60.1";
            leaseStatePath = "/var/lib/kea/dmz.leases";
            domain = "dmz.home.arpa.";
          };
        };

        ipv6Ra = {
          tenant-neon-dmz = slaacRa "tenant-neon-dmz";
        };
      };
    };

  accessIotSrv =
    (mkNode "access-iot-srv" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessIotSrvLink;
        adapterName = "prod-a-iot-srv-ds";
        bridge = "rt-downstream-access-iot-srv";
        interfaceName = "access-iot-srv";
      };

      tenant-neon-iot-srv = tenantPort {
        logicalInterface = "tenant-neon-iot-srv";
        bridge = "iot-srv";
        interfaceName = "iot-srv";
        addr4 = "10.3.51.1/24";
        addr6 = "fd42:dead:beef:351::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns = accessDns {
          addresses = [
            dnsRuntime.requesters.access-iot-srv.ipv4
            dnsRuntime.requesters.access-iot-srv.ipv6
          ];
        };
      };

      advertisements = {
        dhcp4 = {
          tenant-neon-iot-srv = dhcp4Advertisement {
            tenant = "neon-iot-srv";
            interface = "tenant-neon-iot-srv";
            subnet = "10.3.51.0/24";
            poolStart = "10.3.51.100";
            poolEnd = "10.3.51.200";
            router = "10.3.51.1";
            leaseStatePath = "/var/lib/kea/iot-srv.leases";
            domain = "iot-srv.home.arpa.";
          };
        };

        ipv6Ra = {
          tenant-neon-iot-srv = slaacRa "tenant-neon-iot-srv";
        };
      };
    };

  accessIot =
    (mkNode "access-iot" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessIotLink;
        adapterName = "prod-a-iot-ds";
        bridge = "rt-downstream-access-iot";
        interfaceName = "access-iot";
      };

      tenant-neon-iot = tenantPort {
        logicalInterface = "tenant-neon-iot";
        bridge = "iot";
        interfaceName = "iot";
        addr4 = "10.3.50.1/24";
        addr6 = "fd42:dead:beef:350::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns = accessDns {
          addresses = [
            dnsRuntime.requesters.access-iot.ipv4
            dnsRuntime.requesters.access-iot.ipv6
          ];
        };
      };

      advertisements = {
        dhcp4 = {
          tenant-neon-iot = dhcp4Advertisement {
            tenant = "neon-iot";
            interface = "tenant-neon-iot";
            subnet = "10.3.50.0/24";
            poolStart = "10.3.50.100";
            poolEnd = "10.3.50.200";
            router = "10.3.50.1";
            leaseStatePath = "/var/lib/kea/iot.leases";
            domain = "iot.home.arpa.";
            reservations = reservationsFor "neon-iot";
            reservationSource = protectedReservationSource "/run/secrets/devices/";
          };
        };

        ipv6Ra = {
          tenant-neon-iot = slaacRa "tenant-neon-iot";
        };
      };
    };

  accessUnlock =
    (mkNode "access-unlock" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessUnlockLink;
        adapterName = "prod-a-unlock-ds";
        bridge = "rt-downstream-access-unlock";
        interfaceName = "access-unlock";
      };

      tenant-neon-unlock = tenantPort {
        logicalInterface = "tenant-neon-unlock";
        bridge = "unlock";
        interfaceName = "unlock";
        addr4 = "10.3.90.1/24";
        addr6 = "fd42:dead:beef:390::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns = unlockDns [
          dnsRuntime.requesters.access-unlock.ipv4
          dnsRuntime.requesters.access-unlock.ipv6
        ];
      };

      advertisements = {
        dhcp4 = {
          tenant-neon-unlock = dhcp4Advertisement {
            tenant = "neon-unlock";
            interface = "tenant-neon-unlock";
            subnet = "10.3.90.0/24";
            poolStart = "10.3.90.100";
            poolEnd = "10.3.90.200";
            router = "10.3.90.1";
            leaseStatePath = "/var/lib/kea/unlock.leases";
            domain = "unlock.home.arpa.";
          };
        };

        ipv6Ra = {
          tenant-neon-unlock = slaacRa "tenant-neon-unlock";
        };
      };
    };

  accessMgmt =
    (mkNode "access-mgmt" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessMgmtLink;
        adapterName = "prod-a-mgmt-ds";
        bridge = "rt-downstream-access-mgmt";
        interfaceName = "access-mgmt";
      };

      tenant-neon-mgmt = tenantPort {
        logicalInterface = "tenant-neon-mgmt";
        bridge = "mgmt";
        interfaceName = "mgmt";
        addr4 = "10.3.10.1/24";
        addr6 = "fd42:dead:beef:310::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns = accessDns {
          addresses = [
            dnsRuntime.requesters.access-mgmt.ipv4
            dnsRuntime.requesters.access-mgmt.ipv6
          ];
        };
      };

      advertisements = {
        dhcp4 = {
          tenant-neon-mgmt = dhcp4Advertisement {
            tenant = "neon-mgmt";
            interface = "tenant-neon-mgmt";
            subnet = "10.3.10.0/24";
            poolStart = "10.3.10.100";
            poolEnd = "10.3.10.200";
            router = "10.3.10.1";
            leaseStatePath = "/var/lib/kea/mgmt.leases";
            domain = "mgmt.home.arpa.";
          };
        };

        ipv6Ra = {
          tenant-neon-mgmt = slaacRa "tenant-neon-mgmt";
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
    neon-mgmt-dns = {
      ipv4 = [ dnsRuntime.requesters.access-mgmt.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-mgmt.ipv6 ];
    };

    neon-svc-dns = {
      ipv4 = [ dnsRuntime.requesters.access-svc.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-svc.ipv6 ];
    };

    neon-clients-dns = {
      ipv4 = [ dnsRuntime.requesters.access-clients.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-clients.ipv6 ];
    };

    neon-iot-dns = {
      ipv4 = [ dnsRuntime.requesters.access-iot.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-iot.ipv6 ];
    };

    neon-iot-srv-dns = {
      ipv4 = [ dnsRuntime.requesters.access-iot-srv.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-iot-srv.ipv6 ];
    };

    neon-dmz-dns = {
      ipv4 = [ dnsRuntime.requesters.access-dmz.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-dmz.ipv6 ];
    };

    neon-unlock-dns = {
      ipv4 = [ dnsRuntime.requesters.access-unlock.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-unlock.ipv6 ];
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
          mgmt = {
            name = "mgmt";
            vlan = 10;
            parentUplink = "trunk";
          };

          svc = {
            name = "svc";
            vlan = 20;
            parentUplink = "trunk";
          };

          clients = {
            name = "clients";
            vlan = 30;
            parentUplink = "trunk";
          };

          iot = {
            name = "iot";
            vlan = 50;
            parentUplink = "trunk";
          };

          iot-srv = {
            name = "iot-srv";
            vlan = 51;
            parentUplink = "trunk";
          };

          dmz = {
            name = "dmz";
            vlan = 60;
            parentUplink = "trunk";
          };

          unlock = {
            name = "unlock";
            vlan = 90;
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
          rt-downstream-access-svc = { };
          rt-downstream-access-clients = { };
          rt-downstream-access-dmz = { };
          rt-downstream-access-iot-srv = { };
          rt-downstream-access-iot = { };
          rt-downstream-access-unlock = { };
          rt-downstream-access-mgmt = { };
          rt-policy-downstream-svc = { };
          rt-policy-downstream-clients = { };
          rt-policy-downstream-dmz = { };
          rt-policy-downstream-iot-srv = { };
          rt-policy-downstream-iot = { };
          rt-policy-downstream-unlock = { };
          rt-policy-downstream-mgmt = { };
          rt-upstream-policy-svc = { };
          rt-upstream-policy-clients = { };
          rt-upstream-policy-iot-srv = { };
          rt-upstream-policy-iot = { };
          rt-upstream-policy-mgmt = { };
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
          runtimeIfName = port.interface.name;
          transport.hostFacing = false;
        })
        downstreamSelector.ports;

      "${nodeName "upstream-selector"}" = builtins.mapAttrs
        (_: port: {
          kind = "selector-fabric-link";
          link = port.link;
          runtimeIfName = port.interface.name;
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
      ${nodeName "access-clients"} = accessClients;
      ${nodeName "access-svc"} = accessSvc;
      ${nodeName "access-dmz"} = accessDmz;
      ${nodeName "access-iot-srv"} = accessIotSrv;
      ${nodeName "access-iot"} = accessIot;
      ${nodeName "access-unlock"} = accessUnlock;
      ${nodeName "access-mgmt"} = accessMgmt;
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
