let
  prodHost = "s-router-cobalt";
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
    , addr4 ? null
    , addr6 ? null
    ,
    }:
    {
      inherit logicalInterface;
      attach = bridgeAttach bridge;
      interface = {
        name = interfaceName;
        logical = true;
      }
      // (if addr4 == null then { } else { inherit addr4; })
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
        dst = "10.2.60.1";
        scope = "local-access";
        source = "router-self";
      }
    ];
  };

  protectedReservationSource = sourceFile: {
    schema = "gamp-protected-reservation-set-v1";
    sourceClass = "protected";
    inherit sourceFile;
  };

  cobaltReservations = import ./cobalt-reservations.nix;

  reservationsFor = vlan:
    builtins.map
      (deviceId:
        let
          device = cobaltReservations.${deviceId};
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
        (deviceId: cobaltReservations.${deviceId}.scopes ? ${vlan})
        (builtins.attrNames cobaltReservations));

  dhcp4Advertisement =
    { tenant
    , interface
    , subnet
    , poolStart
    , poolEnd
    , router
    , leaseStatePath
    , domain ? "clients.home.arpa."
    , reservations ? null
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
      inherit domain;
      leaseState.path = leaseStatePath;
    }
    // (if reservations == null then { } else { inherit reservations; })
    // (if reservationSource == null then { } else { inherit reservationSource; });

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
  coreVpnOnyxUpstreamLink = "p2p-core-vpn-onyx-upstream-selector";
  upstreamPolicyClientsLink = "p2p-policy-upstream-selector--access-access-clients--uplink-wan";
  upstreamPolicyIotSrvLink = "p2p-policy-upstream-selector--access-access-iot-srv--uplink-wan";
  policyDownstreamClientsLink = "p2p-downstream-selector-policy--access-access-clients";
  policyDownstreamDmzLink = "p2p-downstream-selector-policy--access-access-dmz";
  policyDownstreamIotSrvLink = "p2p-downstream-selector-policy--access-access-iot-srv";
  downstreamAccessClientsLink = "p2p-access-clients-downstream-selector";
  upstreamPolicySvcLink = "p2p-policy-upstream-selector--access-access-svc--uplink-wan";
  policyDownstreamSvcLink = "p2p-downstream-selector-policy--access-access-svc";
  downstreamAccessSvcLink = "p2p-access-svc-downstream-selector";
  downstreamAccessDmzLink = "p2p-access-dmz-downstream-selector";
  downstreamAccessIotSrvLink = "p2p-access-iot-srv-downstream-selector";
  upstreamPolicyIotLink = "p2p-policy-upstream-selector--access-access-iot--uplink-wan";
  policyDownstreamIotLink = "p2p-downstream-selector-policy--access-access-iot";
  downstreamAccessIotLink = "p2p-access-iot-downstream-selector";
  upstreamPolicyClientsVpnLink = "p2p-policy-upstream-selector--access-access-clients-vpn--uplink-onyx";
  policyDownstreamClientsVpnLink = "p2p-downstream-selector-policy--access-access-clients-vpn";
  downstreamAccessClientsVpnLink = "p2p-access-clients-vpn-downstream-selector";

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
            dnsRuntime.requesters.access-clients.clientIpv4
            dnsRuntime.requesters.access-clients.clientIpv6
            dnsRuntime.requesters.access-svc.clientIpv4
            dnsRuntime.requesters.access-svc.clientIpv6
            "${dnsRuntime.requesters.access-iot-srv.ipv4}/32"
            "${dnsRuntime.requesters.access-iot-srv.ipv6}/128"
            "${dnsRuntime.requesters.access-iot.ipv4}/32"
            "${dnsRuntime.requesters.access-iot.ipv6}/128"
            "${dnsRuntime.requesters.access-clients-vpn.ipv4}/32"
            "${dnsRuntime.requesters.access-clients-vpn.ipv6}/128"
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

    core-vpn-onyx = p2pPort {
      link = coreVpnOnyxUpstreamLink;
      adapterName = "cb-us-cvo";
      bridge = "rt-core-vpn-onyx-upstream-selector";
      interfaceName = "core-vpn-onyx";
    };

    policy-clients = p2pPort {
      link = upstreamPolicyClientsLink;
      adapterName = "cb-us-p2";
      bridge = "rt-upstream-policy-clients";
      interfaceName = "policy-clients";
    };

    policy-svc = p2pPort {
      link = upstreamPolicySvcLink;
      adapterName = "cb-us-p1";
      bridge = "rt-upstream-policy-svc";
      interfaceName = "policy-svc";
    };

    policy-iot-srv = p2pPort {
      link = upstreamPolicyIotSrvLink;
      adapterName = "cb-us-p7";
      bridge = "rt-upstream-policy-iot-srv";
      interfaceName = "policy";
    };

    policy-iot = p2pPort {
      link = upstreamPolicyIotLink;
      adapterName = "cb-us-p8";
      bridge = "rt-upstream-policy-iot";
      interfaceName = "policy-iot";
    };

    policy-clients-vpn = p2pPort {
      link = upstreamPolicyClientsVpnLink;
      adapterName = "cb-us-p9";
      bridge = "rt-upstream-policy-clients-vpn";
      interfaceName = "policy-clients-vpn";
    };
  };

  policy = mkNode "policy" {
    upstream-svc = p2pPort {
      link = upstreamPolicySvcLink;
      adapterName = "cb-p-us1";
      bridge = "rt-upstream-policy-svc";
      interfaceName = "upstream-svc";
    };

    upstream-clients = p2pPort {
      link = upstreamPolicyClientsLink;
      adapterName = "cb-p-us2";
      bridge = "rt-upstream-policy-clients";
      interfaceName = "upstream-clients";
    };

    upstream-iot-srv = p2pPort {
      link = upstreamPolicyIotSrvLink;
      adapterName = "cb-p-us7";
      bridge = "rt-upstream-policy-iot-srv";
      interfaceName = "upstream-iot-srv";
    };

    upstream-iot = p2pPort {
      link = upstreamPolicyIotLink;
      adapterName = "cb-p-us8";
      bridge = "rt-upstream-policy-iot";
      interfaceName = "upstream-iot";
    };

    upstream-clients-vpn = p2pPort {
      link = upstreamPolicyClientsVpnLink;
      adapterName = "cb-p-us9";
      bridge = "rt-upstream-policy-clients-vpn";
      interfaceName = "upstream-clients-vpn";
    };

    downstream-svc = p2pPort {
      link = policyDownstreamSvcLink;
      adapterName = "cb-p-ds1";
      bridge = "rt-policy-downstream-svc";
      interfaceName = "downstream-svc";
    };

    downstream-clients = p2pPort {
      link = policyDownstreamClientsLink;
      adapterName = "cb-p-ds2";
      bridge = "rt-policy-downstream-clients";
      interfaceName = "downstream-clients";
    };

    downstream-dmz = p2pPort {
      link = policyDownstreamDmzLink;
      adapterName = "cb-p-ds3";
      bridge = "rt-policy-downstream-dmz";
      interfaceName = "downstream-dmz";
    };

    downstream-iot-srv = p2pPort {
      link = policyDownstreamIotSrvLink;
      adapterName = "cb-p-ds7";
      bridge = "rt-policy-downstream-iot-srv";
      interfaceName = "downstr-iot-srv";
    };

    downstream-iot = p2pPort {
      link = policyDownstreamIotLink;
      adapterName = "cb-p-ds8";
      bridge = "rt-policy-downstream-iot";
      interfaceName = "downstr-iot";
    };

    downstream-clients-vpn = p2pPort {
      link = policyDownstreamClientsVpnLink;
      adapterName = "cb-p-ds9";
      bridge = "rt-policy-downstream-clients-vpn";
      interfaceName = "downstr-clients-vpn";
    };
  };

  downstreamSelector = mkNode "downstream-selector" {
    policy-svc = p2pPort {
      link = policyDownstreamSvcLink;
      adapterName = "cb-ds-p1";
      bridge = "rt-policy-downstream-svc";
      interfaceName = "policy-svc";
    };

    policy-clients = p2pPort {
      link = policyDownstreamClientsLink;
      adapterName = "cb-ds-p2";
      bridge = "rt-policy-downstream-clients";
      interfaceName = "policy-clients";
    };

    policy-dmz = p2pPort {
      link = policyDownstreamDmzLink;
      adapterName = "cb-ds-p3";
      bridge = "rt-policy-downstream-dmz";
      interfaceName = "policy-dmz";
    };

    policy-iot-srv = p2pPort {
      link = policyDownstreamIotSrvLink;
      adapterName = "cb-ds-p7";
      bridge = "rt-policy-downstream-iot-srv";
      interfaceName = "policy-iot-srv";
    };

    policy-iot = p2pPort {
      link = policyDownstreamIotLink;
      adapterName = "cb-ds-p8";
      bridge = "rt-policy-downstream-iot";
      interfaceName = "policy-iot";
    };

    policy-clients-vpn = p2pPort {
      link = policyDownstreamClientsVpnLink;
      adapterName = "cb-ds-p9";
      bridge = "rt-policy-downstream-clients-vpn";
      interfaceName = "policy-clients-vpn";
    };

    access-svc = p2pPort {
      link = downstreamAccessSvcLink;
      adapterName = "cb-ds-a1";
      bridge = "rt-downstream-access-svc";
      interfaceName = "access-svc";
    };

    access-clients = p2pPort {
      link = downstreamAccessClientsLink;
      adapterName = "cb-ds-a2";
      bridge = "rt-downstream-access-clients";
      interfaceName = "access-clients";
    };

    access-dmz = p2pPort {
      link = downstreamAccessDmzLink;
      adapterName = "cb-ds-a3";
      bridge = "rt-downstream-access-dmz";
      interfaceName = "access-dmz";
    };

    access-iot-srv = p2pPort {
      link = downstreamAccessIotSrvLink;
      adapterName = "cb-ds-a7";
      bridge = "rt-downstream-access-iot-srv";
      interfaceName = "access-iot-srv";
    };

    access-iot = p2pPort {
      link = downstreamAccessIotLink;
      adapterName = "cb-ds-a8";
      bridge = "rt-downstream-access-iot";
      interfaceName = "access-iot";
    };

    access-clients-vpn = p2pPort {
      link = downstreamAccessClientsVpnLink;
      adapterName = "cb-ds-a9";
      bridge = "rt-downstream-access-clients-vpn";
      interfaceName = "access-clients-vpn";
    };
  };

  accessClients =
    (mkNode "access-clients" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessClientsLink;
        adapterName = "cb-a2-ds";
        bridge = "rt-downstream-access-clients";
        interfaceName = "access-clients";
      };

      tenant-clients = tenantPort {
        logicalInterface = "tenant-clients";
        bridge = "clients";
        interfaceName = "clients";
        addr4 = "10.2.30.1/24";
        addr6 = "fd42:dead:beef:c1e::1/64";
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
          tenant-clients = dhcp4Advertisement {
            tenant = "clients";
            interface = "tenant-clients";
            subnet = "10.2.30.0/24";
            poolStart = "10.2.30.100";
            poolEnd = "10.2.30.200";
            router = "10.2.30.1";
            leaseStatePath = "/var/lib/kea/clients.leases";
            domain = "clients.home.arpa.";
            reservations = reservationsFor "clients";
            reservationSource = protectedReservationSource "/run/secrets/devices/";
          };
        };

        ipv6Ra = {
          tenant-clients = slaacRa "tenant-clients";
        };
      };
    };
  accessSvc =
    (mkNode "access-svc" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessSvcLink;
        adapterName = "cb-a1-ds";
        bridge = "rt-downstream-access-svc";
        interfaceName = "access-svc";
      };

      tenant-svc = tenantPort {
        logicalInterface = "tenant-svc";
        bridge = "svc";
        interfaceName = "svc";
        addr4 = "10.2.20.1/24";
        addr6 = "fd42:dead:beef:c14::1/64";
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
          tenant-svc = dhcp4Advertisement {
            tenant = "svc";
            interface = "tenant-svc";
            subnet = "10.2.20.0/24";
            poolStart = "10.2.20.100";
            poolEnd = "10.2.20.200";
            router = "10.2.20.1";
            leaseStatePath = "/var/lib/kea/svc.leases";
            domain = "svc.home.arpa.";
            reservationSource = protectedReservationSource "/run/secrets/devices/";
          };
        };

        ipv6Ra = {
          tenant-svc = slaacRa "tenant-svc";
        };
      };
    };

  accessDmz =
    (mkNode "access-dmz" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessDmzLink;
        adapterName = "cb-a3-ds";
        bridge = "rt-downstream-access-dmz";
        interfaceName = "access-dmz";
      };

      tenant-dmz = tenantPort {
        logicalInterface = "tenant-dmz";
        bridge = "dmz";
        interfaceName = "dmz";
        addr4 = "10.2.60.1/24";
        addr6 = "fd42:dead:beef:c3c::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns = localDns [
          dnsRuntime.requesters.access-dmz.ipv4
          dnsRuntime.requesters.access-dmz.ipv6
        ] [ ];
      };

      advertisements = {
        dhcp4 = {
          tenant-dmz = dhcp4Advertisement {
            tenant = "dmz";
            interface = "tenant-dmz";
            subnet = "10.2.60.0/24";
            poolStart = "10.2.60.100";
            poolEnd = "10.2.60.200";
            router = "10.2.60.1";
            leaseStatePath = "/var/lib/kea/dmz.leases";
            domain = "dmz.home.arpa.";
          };
        };

        ipv6Ra = {
          tenant-dmz = slaacRa "tenant-dmz";
        };
      };
    };

  accessIotSrv =
    (mkNode "access-iot-srv" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessIotSrvLink;
        adapterName = "cb-a7-ds";
        bridge = "rt-downstream-access-iot-srv";
        interfaceName = "access-iot-srv";
      };

      tenant-iot-srv = tenantPort {
        logicalInterface = "tenant-iot-srv";
        bridge = "iot-srv";
        interfaceName = "iot-srv";
        addr4 = "10.2.51.1/24";
        addr6 = "fd42:dead:beef:c33::1/64";
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
          tenant-iot-srv = dhcp4Advertisement {
            tenant = "iot-srv";
            interface = "tenant-iot-srv";
            subnet = "10.2.51.0/24";
            poolStart = "10.2.51.100";
            poolEnd = "10.2.51.200";
            router = "10.2.51.1";
            leaseStatePath = "/var/lib/kea/iot-srv.leases";
            domain = "iot-srv.home.arpa.";
          };
        };

        ipv6Ra = {
          tenant-iot-srv = slaacRa "tenant-iot-srv";
        };
      };
    };

  accessIot =
    (mkNode "access-iot" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessIotLink;
        adapterName = "cb-a8-ds";
        bridge = "rt-downstream-access-iot";
        interfaceName = "access-iot";
      };

      tenant-iot = tenantPort {
        logicalInterface = "tenant-iot";
        bridge = "iot";
        interfaceName = "iot";
        addr4 = "10.2.50.1/24";
        addr6 = "fd42:dead:beef:c32::1/64";
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
          tenant-iot = dhcp4Advertisement {
            tenant = "iot";
            interface = "tenant-iot";
            subnet = "10.2.50.0/24";
            poolStart = "10.2.50.100";
            poolEnd = "10.2.50.200";
            router = "10.2.50.1";
            leaseStatePath = "/var/lib/kea/iot.leases";
            domain = "iot.home.arpa.";
            reservations = reservationsFor "iot";
            reservationSource = protectedReservationSource "/run/secrets/devices/";
          };
        };

        ipv6Ra = {
          tenant-iot = slaacRa "tenant-iot";
        };
      };
    };

  accessClientsVpn =
    (mkNode "access-clients-vpn" {
      transit-downstream-selector = p2pPort {
        link = downstreamAccessClientsVpnLink;
        adapterName = "cb-a9-ds";
        bridge = "rt-downstream-access-clients-vpn";
        interfaceName = "access-clients-vpn";
      };

      tenant-clients-vpn = tenantPort {
        logicalInterface = "tenant-clients-vpn";
        bridge = "clients-vpn";
        interfaceName = "clients-vpn";
        addr4 = "10.2.31.1/24";
        addr6 = "fd42:dead:beef:c1f::1/64";
      };
    })
    // {
      statePolicy = persistentDhcpState;

      services = {
        dns = accessDns {
          addresses = [
            dnsRuntime.requesters.access-clients-vpn.ipv4
            dnsRuntime.requesters.access-clients-vpn.ipv6
          ];
        };
      };

      advertisements = {
        dhcp4 = {
          tenant-clients-vpn = dhcp4Advertisement {
            tenant = "clients-vpn";
            interface = "tenant-clients-vpn";
            subnet = "10.2.31.0/24";
            poolStart = "10.2.31.100";
            poolEnd = "10.2.31.200";
            router = "10.2.31.1";
            leaseStatePath = "/var/lib/kea/clients-vpn.leases";
            domain = "clients-vpn.home.arpa.";
            reservationSource = protectedReservationSource "/run/secrets/devices/";
          };
        };

        ipv6Ra = {
          tenant-clients-vpn = slaacRa "tenant-clients-vpn";
        };
      };
    };

  vpnOnyx = mkNode "core-vpn-onyx" {
    upstream-selector = p2pPort {
      link = coreVpnOnyxUpstreamLink;
      adapterName = "cb-cvo-us";
      bridge = "rt-core-vpn-onyx-upstream-selector";
      interfaceName = "upstream-selector";
    };

    onyx = uplinkPort {
      uplink = "onyx";
      bridge = "br-onyx";
      interfaceName = "onyx";
    };

    tenant-iot-srv = tenantPort {
      logicalInterface = "tenant-iot-srv";
      bridge = "iot-srv";
      interfaceName = "iot-srv";
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

    cobalt-svc-dns = {
      ipv4 = [ dnsRuntime.requesters.access-svc.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-svc.ipv6 ];
    };

    cobalt-clients-dns = {
      ipv4 = [ dnsRuntime.requesters.access-clients.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-clients.ipv6 ];
    };

    cobalt-dmz-dns = {
      ipv4 = [ dnsRuntime.requesters.access-dmz.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-dmz.ipv6 ];
    };

    cobalt-iot-srv-dns = {
      ipv4 = [ dnsRuntime.requesters.access-iot-srv.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-iot-srv.ipv6 ];
    };

    cobalt-iot-dns = {
      ipv4 = [ dnsRuntime.requesters.access-iot.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-iot.ipv6 ];
    };

    cobalt-clients-vpn-dns = {
      ipv4 = [ dnsRuntime.requesters.access-clients-vpn.ipv4 ];
      ipv6 = [ dnsRuntime.requesters.access-clients-vpn.ipv6 ];
    };
  };

  deployment = {
    hosts = {
      ${prodHost} = {
        wanUplink = "upstream-core";

        hostManagement = {
          logicalInterface = "vlan300";
          link = {
            kind = "bridge";
            name = "br-wan";
          };
          addressAcquisition = {
            ipv4 = "dhcp";
            ipv6 = "disabled";
            acceptRA = false;
            useDns = false;
            defaultRoute = false;
          };
        };

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

          onyx = {
            bridge = "br-onyx";
            parent = "onyx-wg";
            ipv4 = {
              method = "none";
            };
            ipv6 = {
              method = "none";
            };
            upstream = "onyx";
          };

          trunk = {
            parent = "eth0";
            bridge = "br-lan-trunk";
            mode = "trunk";
          };
        };

        transitBridges = {
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

          clients-vpn = {
            name = "clients-vpn";
            vlan = 31;
            parentUplink = "trunk";
          };
        };

        bridgeNetworks = {
          rt-core-upstream-selector = { };
          rt-core-vpn-onyx-upstream-selector = { };
          rt-downstream-access-svc = { };
          rt-downstream-access-clients = { };
          rt-downstream-access-dmz = { };
          rt-downstream-access-iot-srv = { };
          rt-policy-downstream-svc = { };
          rt-policy-downstream-clients = { };
          rt-policy-downstream-dmz = { };
          rt-policy-downstream-iot-srv = { };
          rt-upstream-policy-svc = { };
          rt-upstream-policy-clients = { };
          rt-upstream-policy-iot-srv = { };
          rt-downstream-access-iot = { };
          rt-policy-downstream-iot = { };
          rt-upstream-policy-iot = { };
          rt-downstream-access-clients-vpn = { };
          rt-policy-downstream-clients-vpn = { };
          rt-upstream-policy-clients-vpn = { };
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
      ${nodeName "upstream-selector"} = upstreamSelector // { ports = { }; };
      ${nodeName "policy"} = policy;
      ${nodeName "downstream-selector"} = downstreamSelector // { ports = { }; };
      ${nodeName "access-clients"} = accessClients;
      ${nodeName "access-svc"} = accessSvc;
      ${nodeName "access-dmz"} = accessDmz;
      ${nodeName "access-iot-srv"} = accessIotSrv;
      ${nodeName "access-iot"} = accessIot;
      ${nodeName "access-clients-vpn"} = accessClientsVpn;
      ${nodeName "core-vpn-onyx"} = vpnOnyx;
    };
  };

  controlPlane = {
    sites = {
      esp0xdeadbeef = {
        cobalt = {
          overlays = {
            onyx = {
              provider = "wireguard";
              providerBootstrapDns = {
                forwarders = [
                  "10.128.0.1"
                  "fd7d:76ee:e68f:a993::1"
                ];
              };
              providerContract = {
                id = "onyx";
                provider = {
                  class = "commercial-imported";
                  mode = "egress-only";
                  prefixAuthority = "host-only-128";
                };
                interfaces = {
                  wan = "iot-srv";
                  lan = "up-sel";
                  vpn = "overlay-onyx";
                };
                profile = {
                  mode = "generated-peer";
                  generatedPeer = {
                    privateKeyFile = "/run/secrets/onyx-private-key";
                    addressesFile = "/run/secrets/onyx-address";
                    dnsFile = "/run/secrets/onyx-dns";
                    mtu = 1320;
                    peers = [
                      {
                        publicKeyFile = "/run/secrets/onyx-public-key";
                        endpointFile = "/run/secrets/onyx-endpoint";
                        presharedKeyFile = "/run/secrets/onyx-preshared-key";
                        allowedIPs = [
                          "0.0.0.0/0"
                          "::/0"
                        ];
                        persistentKeepalive = 15;
                      }
                    ];
                  };
                };
                runtime = {
                  uuidFile = "/run/network-renderer-wireguard/onyx.uuid";
                  generatedConfigPath = "/run/network-renderer-wireguard/onyx.conf";
                };
                lan = {
                  ipv4.address = "10.1.1.2/32";
                  ipv6.address = "fd42:dead:beef:2900::2/128";
                };
                wan = {
                  ipv4.method = "auto";
                  ipv6.method = "auto";
                };
                dns.mode = "default";
                firewall.mode = null;
                nat = {
                  ipv4 = {
                    enable = true;
                    sourceCidrs = [ "10.2.30.0/24" "10.2.31.0/24" ];
                  };
                  ipv6 = {
                    enable = true;
                    sourceCidrs = [ "fd42:dead:beef:c1e::/64" "fd42:dead:beef:c1f::/64" ];
                  };
                };
                publicIngress = [ ];
                portForwards = [ ];
                services = {
                  dhcp4.enable = false;
                  ra.enable = false;
                  healthCheck.enable = false;
                };
              };
              runtimeNodes = { };
            };
          };
        };
      };
    };
  };
}
