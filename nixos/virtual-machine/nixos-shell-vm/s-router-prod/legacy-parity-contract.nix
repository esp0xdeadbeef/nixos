{ config, lib, outPath, ... }:

let
  dnsRuntime = import "${outPath}/prod-network/current/dns-runtime-addresses.nix";
  prodIntent = import "${outPath}/prod-network/current/intent.nix";
  prodInventory = import "${outPath}/prod-network/current/inventory.nix";
  prodSite = prodIntent.esp0xdeadbeef.site-a;
  vlan3AuthorityRecords =
    prodInventory.realization.nodes."esp0xdeadbeef-site-a-access-vlan3".services.dns.localRecords;
  vlan3AuthorityNames = map (record: record.name) vlan3AuthorityRecords;
  dnsResolver = dnsRuntime.resolver;
  renderedDnsResolver = dnsResolver // {
    ipv6 = "fd42:dead:beef:1000:0:0:0:6";
  };
  vlan2Dns = dnsRuntime.requesters.access-vlan2;
  vlan3Dns = dnsRuntime.requesters.access-vlan3;
  vlan7Dns = dnsRuntime.requesters.access-vlan7;

  expectedQemuNetworkingOptions = [
    "-nic none"
    "-nic bridge,br=vmbr4,mac=52:54:00:12:34:56,model=virtio-net-pci"
    "-nic bridge,br=vmbr1,mac=52:54:00:12:34:57,model=virtio-net-pci"
  ];

  expectedContainers = [
    "access-vlan3"
    "access-vlan2"
    "access-vlan7"
    "core"
    "downstream-selector"
    "policy"
    "upstream-selector"
  ];

  netdevBridgeNames =
    lib.pipe (config.systemd.network.netdevs or { }) [
      builtins.attrValues
      (builtins.map (netdev: netdev.netdevConfig or { }))
      (builtins.filter (netdevConfig: (netdevConfig.Kind or null) == "bridge"))
      (builtins.map (netdevConfig: netdevConfig.Name or null))
      (builtins.filter (name: name != null))
    ];

  containerNames = builtins.attrNames (config.containers or { });

  coreExtraVethBridges =
    lib.pipe (config.containers.core.extraVeths or { }) [
      builtins.attrValues
      (builtins.map (veth: veth.hostBridge or null))
      (builtins.filter (bridge: bridge != null))
    ];

  hasExpectedContainers =
    builtins.all (name: builtins.elem name containerNames) expectedContainers
    && !(builtins.hasAttr "external-isp" (config.containers or { }));

  servicesFor =
    containerName:
      config.containers.${containerName}.config.systemd.services or { };

  hasRenderedService =
    containerName: stem:
    builtins.any
      (name: builtins.match "${stem}-[0-9]+" name != null)
      (builtins.attrNames (servicesFor containerName));

  requiredRendererIpv6ServiceStems = {
    core = [
      "s88-delegated-prefix-route-ens3"
    ];
    upstream-selector = [
      "s88-delegated-prefix-route-policy"
      "s88-delegated-prefix-route-policy-vlan2"
      "s88-delegated-prefix-route-policy-vlan3"
      "s88-delegated-prefix-policy-route-policy-1001"
      "s88-delegated-prefix-policy-route-policy-1002"
      "s88-delegated-prefix-policy-route-policy-vlan2-1001"
      "s88-delegated-prefix-policy-route-policy-vlan2-1003"
      "s88-delegated-prefix-policy-route-policy-vlan3-1001"
      "s88-delegated-prefix-policy-route-policy-vlan3-1004"
    ];
    policy = [
      "s88-delegated-prefix-route-down-vlan2"
      "s88-delegated-prefix-route-down-vlan3"
      "s88-delegated-prefix-route-downstr-vlan7"
      "s88-delegated-prefix-policy-route-down-vlan2-1001"
      "s88-delegated-prefix-policy-route-down-vlan2-1002"
      "s88-delegated-prefix-policy-route-down-vlan2-1004"
      "s88-delegated-prefix-policy-route-down-vlan3-1001"
      "s88-delegated-prefix-policy-route-down-vlan3-1002"
      "s88-delegated-prefix-policy-route-down-vlan3-1003"
      "s88-delegated-prefix-policy-route-downstr-vlan7-1001"
      "s88-delegated-prefix-policy-route-downstr-vlan7-1002"
      "s88-delegated-prefix-policy-route-downstr-vlan7-1006"
    ];
    downstream-selector = [
      "s88-delegated-prefix-route-access-vlan2"
      "s88-delegated-prefix-route-access-vlan3"
      "s88-delegated-prefix-route-access-vlan7"
      "s88-delegated-prefix-policy-route-access-vlan2-1001"
      "s88-delegated-prefix-policy-route-access-vlan2-1004"
      "s88-delegated-prefix-policy-route-access-vlan3-1002"
      "s88-delegated-prefix-policy-route-access-vlan3-1005"
      "s88-delegated-prefix-policy-route-access-vlan7-1003"
      "s88-delegated-prefix-policy-route-access-vlan7-1006"
    ];
  };

  hasRendererNativeIpv6Routes =
    builtins.all
      (containerName:
        builtins.all
          (hasRenderedService containerName)
          requiredRendererIpv6ServiceStems.${containerName})
      (builtins.attrNames requiredRendererIpv6ServiceStems)
    && builtins.all
      (containerName:
        builtins.any
          (lib.hasPrefix "s88-delegated-prefix-route-")
          (builtins.attrNames (servicesFor containerName)))
      expectedContainers;

  tenantIpv6RouteContainers = [
    "core"
    "upstream-selector"
    "policy"
    "downstream-selector"
  ];

  hasNoExactTenantIpv6RouteCompatibility =
    builtins.all
      (containerName: !(builtins.hasAttr "s-router-prod-ipv6-routes" (servicesFor containerName)))
      tenantIpv6RouteContainers;

  expectedDnsForwarders = [
    renderedDnsResolver.ipv4
    renderedDnsResolver.ipv6
  ];

  unboundForwardersFor =
    containerName:
    let
      settings = config.containers.${containerName}.config.services.unbound.settings or { };
      forwardZones = settings."forward-zone" or [ ];
    in
    lib.unique (
      lib.flatten (
        map (zone: zone."forward-addr" or [ ]) (
          builtins.filter (zone: (zone.name or null) == ".") forwardZones
        )
      )
    );

  unboundForwardZonesFor =
    containerName:
      config.containers.${containerName}.config.services.unbound.settings."forward-zone" or [ ];

  unboundServerFor =
    containerName:
      config.containers.${containerName}.config.services.unbound.settings.server or { };

  hasVlan2RuntimeLocalDns =
    let
      server = unboundServerFor "access-vlan2";
      forwardZones = unboundForwardZonesFor "access-vlan2";
      zoneByName = builtins.listToAttrs (
        map
          (zone: {
            name = zone.name;
            value = zone;
          })
          forwardZones
      );
      localData = server."local-data" or [ ];
    in
    vlan3AuthorityNames != [ ]
    && builtins.elem "lan. static" (server.local-zone or [ ])
    && builtins.elem "1.168.192.in-addr.arpa. static" (server.local-zone or [ ])
    && builtins.all
      (name: builtins.elem "${name} transparent" (server.local-zone or [ ]))
      vlan3AuthorityNames
    && builtins.elem "/run/unbound/s-router-prod-vlan2-local.conf" (server.include or [ ])
    && builtins.all
      (name:
        !(builtins.any (record: lib.hasInfix name record) localData)
        && (zoneByName.${name}."forward-addr" or [ ]) == [
          vlan3Dns.ipv4
          vlan3Dns.ipv6
        ]
        && (zoneByName.${name}."forward-first" or true) == false)
      vlan3AuthorityNames
    && builtins.hasAttr "gen-s-router-prod-vlan2-reservation-dns"
      config.containers.access-vlan2.config.systemd.services;

  hasVlan3LocalSharingDns =
    let
      server = unboundServerFor "access-vlan3";
      forwardZones = unboundForwardZonesFor "access-vlan3";
      zoneByName = builtins.listToAttrs (
        map
          (zone: {
            name = zone.name;
            value = zone;
          })
          forwardZones
      );
    in
    (server.interface or [ ]) == [
      "127.0.0.1"
      "::1"
      vlan3Dns.ipv4
      vlan3Dns.ipv6
    ]
    && (server."local-zone" or [ ]) == [
      "lan. transparent"
      ". refuse"
    ]
    && (server."access-control" or [ ]) == [
      "127.0.0.0/8 allow"
      "::1/128 allow"
      "${vlan3Dns.clientIpv4} allow"
      "${vlan3Dns.clientIpv6} allow"
      "${vlan2Dns.clientIpv4} refuse_non_local"
      "fd42:1:0:0:0:0:0:0/64 refuse_non_local"
    ]
    && builtins.elem ''"s-nebula-container.lan. IN A 192.168.3.10"'' (server."local-data" or [ ])
    && builtins.elem
      ''"s-nebula-container.lan. IN AAAA fd42:dead:beef:3::1337:dead:beef"''
      (server."local-data" or [ ])
    && builtins.length forwardZones == 2
    && (zoneByName."lan."."forward-addr" or [ ]) == [
      vlan2Dns.ipv4
      vlan2Dns.ipv6
    ]
    && (zoneByName."lan."."forward-first" or true) == false
    && (zoneByName."1.168.192.in-addr.arpa."."forward-addr" or [ ]) == [
      vlan2Dns.ipv4
      vlan2Dns.ipv6
    ]
    && (zoneByName."1.168.192.in-addr.arpa."."forward-first" or true) == false
    && (server."outgoing-interface" or [ ]) == [
      vlan3Dns.ipv4
      vlan3Dns.ipv6
    ];

  hasVlan2LocalOnlyPeerAcl =
    let
      server = unboundServerFor "access-vlan2";
    in
    (server."access-control" or [ ]) == [
      "127.0.0.0/8 allow"
      "::1/128 allow"
      "${vlan2Dns.clientIpv4} allow"
      "${vlan2Dns.clientIpv6} allow"
      "${vlan3Dns.ipv4}/32 refuse_non_local"
      "${vlan3Dns.ipv6}/128 refuse_non_local"
    ];

  dnsNftScriptFor =
    containerName:
      config.containers.${containerName}.config.systemd.services.nft-allow-dns-service.script or "";

  dnsNftSurfaceFor =
    containerName:
    dnsNftScriptFor containerName
    + (config.containers.${containerName}.config.networking.nftables.ruleset or "");

  hasStatelessRuleLine =
    ruleset: fragments:
    builtins.any
      (line:
      builtins.all (fragment: lib.hasInfix fragment line) fragments
      && !(lib.hasInfix "ct state" line))
      (lib.splitString "\n" ruleset);

  dnsEgressFragments = {
    access-vlan2 = [
      "ip saddr ${vlan2Dns.ipv4} ip daddr ${dnsResolver.ipv4} udp dport 53"
      "ip saddr ${vlan2Dns.ipv4} ip daddr ${dnsResolver.ipv4} tcp dport 53"
      "ip6 saddr ${vlan2Dns.ipv6} ip6 daddr ${renderedDnsResolver.ipv6} udp dport 53"
      "ip6 saddr ${vlan2Dns.ipv6} ip6 daddr ${renderedDnsResolver.ipv6} tcp dport 53"
    ];

    access-vlan7 = [
      "ip saddr ${vlan7Dns.ipv4} ip daddr ${dnsResolver.ipv4} udp dport 53"
      "ip saddr ${vlan7Dns.ipv4} ip daddr ${dnsResolver.ipv4} tcp dport 53"
      "ip6 saddr ${vlan7Dns.ipv6} ip6 daddr ${renderedDnsResolver.ipv6} udp dport 53"
      "ip6 saddr ${vlan7Dns.ipv6} ip6 daddr ${renderedDnsResolver.ipv6} tcp dport 53"
    ];
  };

  hasDnsEgressRules =
    containerName:
    let
      script = dnsNftSurfaceFor containerName;
    in
    builtins.all (fragment: lib.hasInfix fragment script) dnsEgressFragments.${containerName};

  hasCoreRecursiveDns =
    let
      server = unboundServerFor "core";
      forwarders = unboundForwardersFor "core";
    in
    (server.interface or [ ]) == [
      "127.0.0.1"
      "::1"
      renderedDnsResolver.ipv4
      renderedDnsResolver.ipv6
    ]
    && (server."access-control" or [ ]) == [
      "127.0.0.0/8 allow"
      "::1/128 allow"
      "${vlan2Dns.clientIpv4} allow"
      "${vlan2Dns.ipv4}/32 allow"
      "${vlan7Dns.ipv4}/32 allow"
      "fd42:1:0:0:0:0:0:0/64 allow"
      "${vlan2Dns.ipv6}/128 allow"
      "${vlan7Dns.ipv6}/128 allow"
    ]
    && !(server ? "outgoing-interface")
    && forwarders == [ ];

  hasCoreDnsInputRules =
    let
      ruleset = dnsNftSurfaceFor "core";
    in
    builtins.all (fragment: lib.hasInfix fragment ruleset) [
      "ip daddr ${dnsResolver.ipv4} udp dport 53"
      "ip daddr ${dnsResolver.ipv4} tcp dport 53"
      "ip6 daddr ${renderedDnsResolver.ipv6} udp dport 53"
      "ip6 daddr ${renderedDnsResolver.ipv6} tcp dport 53"
    ];

  desiredDnsIntent = prodSite.recursiveDnsIntent;
  desiredLocalDnsIntent = prodSite.localDnsSharingIntent;
  activeDnsServicesByName = builtins.listToAttrs (
    map
      (service: {
        name = service.name;
        value = service;
      })
      prodSite.communicationContract.services
  );
  activeDnsRelationsById = builtins.listToAttrs (
    map
      (relation: {
        name = relation.id;
        value = relation;
      })
      prodSite.communicationContract.relations
  );
  desiredDnsRelationsById = builtins.listToAttrs (
    map
      (relation: {
        name = relation.id;
        value = relation;
      })
      desiredDnsIntent.relations
  );

  hasCoreDnsIntent =
    activeDnsServicesByName.vlan2-dns.providers == [ "vlan2-dns" ]
    && activeDnsServicesByName.vlan7-dns.providers == [ "vlan7-dns" ]
    && (activeDnsRelationsById.allow-vlan2-dns-to-wan.from or { }) == {
      kind = "service";
      name = "vlan2-dns";
    }
    && (activeDnsRelationsById.allow-vlan7-dns-to-wan.from or { }) == {
      kind = "service";
      name = "vlan7-dns";
    }
    && builtins.any
      (service:
        service.name == "core-dns"
        && service.providerNode == "core"
        && service.addressAuthority == "model-allocated-service-prefix")
      desiredDnsIntent.services
    && (desiredDnsRelationsById.allow-vlan2-dns-to-core-dns.from or { }) == {
      kind = "service";
      name = "vlan2-dns";
    }
    && (desiredDnsRelationsById.allow-vlan2-to-core-dns.from or { }) == {
      kind = "tenant";
      name = "vlan2";
    }
    && (desiredDnsRelationsById.allow-vlan2-to-core-dns.to or { }) == {
      kind = "service";
      name = "core-dns";
    }
    && (desiredDnsRelationsById.allow-vlan2-dns-to-core-dns.to or { }) == {
      kind = "service";
      name = "core-dns";
    }
    && (desiredDnsRelationsById.allow-vlan7-dns-to-core-dns.to or { }) == {
      kind = "service";
      name = "core-dns";
    }
    && (desiredDnsRelationsById.allow-core-dns-to-wan.from or { }) == {
      kind = "service";
      name = "core-dns";
    }
    && (desiredDnsRelationsById.deny-vlan2-dns-to-wan.action or null) == "deny"
    && (desiredDnsRelationsById.deny-vlan7-dns-to-wan.action or null) == "deny"
    && builtins.all
      (binding:
        binding.upstreamResolver.name == "core-dns"
        && binding.upstreamResolver.node == "core"
        && binding.allowedAddressFamilies == [
          "ipv4"
          "ipv6"
        ]
        && binding.directPublicFallback == false)
      desiredDnsIntent.bindings;

  hasLocalDnsSharingIntent =
    let
      activeRelation = activeDnsRelationsById.allow-vlan3-dns-to-vlan2-dns;
      vlan2RequesterRelation = activeDnsRelationsById.allow-vlan2-dns-to-vlan3-dns;
      desiredRelation = desiredLocalDnsIntent.relation;
    in
    vlan2RequesterRelation == {
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
    && activeRelation.priority < activeDnsRelationsById.deny-vlan3-to-vlan2.priority
    && activeRelation.from == desiredRelation.from
    && activeRelation.to == desiredRelation.to
    && activeRelation.trafficType == "dns"
    && activeRelation.returnBehavior == "symmetric"
    && desiredLocalDnsIntent.namespace == "lan."
    && desiredLocalDnsIntent.requester.service == "vlan3-dns"
    && desiredLocalDnsIntent.requester.recursion == false
    && desiredLocalDnsIntent.requester.publicFallback == false
    && desiredLocalDnsIntent.requester.allowedNamespaces == [
      "lan."
      "1.168.192.in-addr.arpa."
    ]
    && desiredLocalDnsIntent.providerPolicy == {
      source = "vlan3-dns";
      action = "refuse_non_local";
    }
    && desiredLocalDnsIntent.lateralPolicy == {
      source = "vlan2";
      target = "vlan3-dns";
      localData = true;
      recursion = false;
      transitiveEgress = false;
      action = "refuse_non_local";
    };

  keaServiceFor =
    containerName: vlanName:
      config.containers.${containerName}.config.systemd.services."kea-dhcp4-${vlanName}" or { };

  keaGenServiceFor =
    containerName: vlanName:
      config.containers.${containerName}.config.systemd.services."gen-kea-${vlanName}" or { };

  execStartPostList =
    value:
    if builtins.isList value then
      value
    else if value == null then
      [ ]
    else
      [ value ];

  hasNativeKeaLeaseState =
    let
      hasContainer =
        containerName: vlanName:
        let
          keaService = keaServiceFor containerName vlanName;
          genService = keaGenServiceFor containerName vlanName;
          postHooks = execStartPostList (genService.serviceConfig.ExecStartPost or null);
        in
        (keaService.serviceConfig.StateDirectory or null) == "kea"
        && builtins.all
          (hook: !(lib.hasInfix "rewrite-kea-${vlanName}-lease-path" (toString hook)))
          postHooks;
    in
    hasContainer "access-vlan2" "vlan2"
    && hasContainer "access-vlan3" "vlan3"
    && hasContainer "access-vlan7" "vlan7";

  hasNativeProtectedReservations =
    let
      hasContainer =
        containerName: vlanName: secretName: sourceFile:
        let
          genService = keaGenServiceFor containerName vlanName;
          execStart = toString (genService.serviceConfig.ExecStart or "");
          postHooks = execStartPostList (genService.serviceConfig.ExecStartPost or null);
          bindMounts = config.containers.${containerName}.bindMounts or { };
        in
        builtins.hasAttr secretName config.sops.secrets
        && builtins.hasAttr sourceFile bindMounts
        && lib.hasInfix "runtime-reservation-materializer.py" execStart
        && lib.hasInfix "--source ${sourceFile}" execStart
        && builtins.all
          (hook: !(lib.hasInfix "apply-s-router-prod-${vlanName}-kea-reservation" (toString hook)))
          postHooks;
    in
    hasContainer
      "access-vlan2"
      "vlan2"
      "s-router-prod-vlan2-reservations-json"
      "/run/secrets/s-router-prod-vlan2-reservations.json"
    && hasContainer
      "access-vlan3"
      "vlan3"
      "s-router-prod-vlan3-reservations-json"
      "/run/secrets/s-router-prod-vlan3-reservations.json";

  coreNftables = config.containers.core.config.networking.nftables.ruleset;
  accessVlan2Nftables = config.containers.access-vlan2.config.networking.nftables.ruleset;
  accessVlan3Nftables = config.containers.access-vlan3.config.networking.nftables.ruleset;
  downstreamSelectorNftables =
    config.containers.downstream-selector.config.networking.nftables.ruleset;
  policyNftables = config.containers.policy.config.networking.nftables.ruleset;
  upstreamSelectorNftables =
    config.containers.upstream-selector.config.networking.nftables.ruleset;

  hasNebulaPublicIngressRules =
    builtins.all (fragment: lib.hasInfix fragment coreNftables) [
      ''iifname "ppp0" oifname "ens3" ct status dnat meta nfproto ipv4 ip daddr 192.168.3.10 meta l4proto udp udp dport 4242 accept comment "allow-wan-to-s-nebula-container"''
      ''iifname "ppp0" oifname "ens3" ct status dnat meta nfproto ipv4 ip daddr 192.168.3.10 meta l4proto tcp tcp dport 4242 accept comment "allow-wan-to-s-nebula-container"''
      ''iifname "ppp0" meta l4proto udp udp dport 4242 dnat to 192.168.3.10:4242 comment "allow-wan-to-s-nebula-container"''
      ''iifname "ppp0" meta l4proto tcp tcp dport 4242 dnat to 192.168.3.10:4242 comment "allow-wan-to-s-nebula-container"''
      ''oifname "ens3" ip daddr 192.168.3.10 meta l4proto udp udp dport 4242 snat to 10.19.0.3 comment "allow-wan-to-s-nebula-container-source-translation"''
      ''oifname "ens3" ip daddr 192.168.3.10 meta l4proto tcp tcp dport 4242 snat to 10.19.0.3 comment "allow-wan-to-s-nebula-container-source-translation"''
    ];

  hasStatefulVlan3Return =
    lib.hasInfix
      ''iifname "down-vlan3" oifname "down-vlan2" ct state established,related accept comment "allow-vlan2-to-vlan3"''
      policyNftables;

  hasIpv6CompatibilityGlue =
    builtins.hasAttr "dhcpcd-ipv6" (servicesFor "core")
    && builtins.hasAttr "s-router-prod-nebula-ipv6-firewall" (servicesFor "core")
    && builtins.hasAttr "s-router-prod-nebula-ipv6-firewall" (servicesFor "upstream-selector")
    && builtins.all (fragment: lib.hasInfix fragment coreNftables) [
      "s-router-prod-dhcpv6-replies"
      "s-router-prod-nebula6-forward-udp"
      "s-router-prod-nebula6-forward-tcp"
    ]
    && builtins.all (fragment: lib.hasInfix fragment upstreamSelectorNftables) [
      "s-router-prod-nebula4-forward-udp"
      "s-router-prod-nebula4-forward-tcp"
      "s-router-prod-nebula6-forward-udp"
      "s-router-prod-nebula6-forward-tcp"
    ];

  hasRoute =
    containerName: networkName: destination: gateway:
    builtins.any
      (route:
      (route.Destination or null) == destination
      && (route.Gateway or null) == gateway)
      (config.containers.${containerName}.config.systemd.network.networks.${networkName}.routes or [ ]);

  hasSourcePolicyRule =
    accessName: networkName: family: source:
    builtins.any
      (rule:
      (rule.Family or null) == family
      && (rule.From or null) == source
      && (rule.Table or null) == 1002
      && (rule.IncomingInterface or null) == null)
      (
        config.containers.${accessName}.config.systemd.network.networks.${networkName}.routingPolicyRules or [ ]
      );

  hasTableRoute =
    containerName: networkName: destination: gateway: table:
    builtins.any
      (route:
      (route.Destination or null) == destination
      && (route.Gateway or null) == gateway
      && (route.Table or null) == table)
      (config.containers.${containerName}.config.systemd.network.networks.${networkName}.routes or [ ]);

  hasRoutingPolicyRule =
    containerName: networkName: expected:
    builtins.any
      (rule:
      builtins.all
        (name: (rule.${name} or null) == expected.${name})
        (builtins.attrNames expected))
      (
        config.containers.${containerName}.config.systemd.network.networks.${networkName}.routingPolicyRules or [ ]
      );

  hasVlan2InternetRoutes =
    hasTableRoute "access-vlan2" "10-access-vlan2" "0.0.0.0/0" "10.10.0.1" 1002
    && hasRoutingPolicyRule "access-vlan2" "10-access-vlan2" {
      Family = "ipv4";
      From = "192.168.1.0/24";
      IncomingInterface = "lan2";
      Priority = 1002;
      Table = 1002;
    }
    && hasTableRoute "downstream-selector" "10-policy-vlan2" "0.0.0.0/0" "10.10.0.9" 1004
    && hasRoutingPolicyRule "downstream-selector" "10-policy-vlan2" {
      Family = "ipv4";
      From = "192.168.1.0/24";
      IncomingInterface = "access-vlan2";
      Priority = 1004;
      Table = 1004;
    }
    && hasTableRoute "policy" "10-upstream-vlan2" "0.0.0.0/0" "10.10.0.15" 1004
    && hasRoutingPolicyRule "policy" "10-upstream-vlan2" {
      Family = "ipv4";
      From = "192.168.1.0/24";
      IncomingInterface = "down-vlan2";
      Priority = 1004;
      Table = 1004;
    }
    && hasTableRoute "upstream-selector" "10-core" "0.0.0.0/0" "10.10.0.6" 1001
    && hasRoutingPolicyRule "upstream-selector" "10-core" {
      Family = "ipv4";
      From = "192.168.1.0/24";
      IncomingInterface = "policy-vlan2";
      Priority = 1001;
      Table = 1001;
    }
    && hasRoute "core" "10-ens3" "192.168.1.0/24" "10.10.0.7";

  hasVlan2InternetFirewallAndNat =
    builtins.all (fragment: lib.hasInfix fragment accessVlan2Nftables) [
      ''iifname "lan2" oifname "access-vlan2" accept comment "selector-handoff-forward--access-vlan2--selector-transport-to-access-to-selector--fabric"''
      ''iifname "access-vlan2" oifname "lan2" ct state established,related accept comment "selector-handoff-reverse--access-vlan2--access-to-selector-to-selector-transport--fabric"''
    ]
    && builtins.all (fragment: lib.hasInfix fragment downstreamSelectorNftables) [
      ''iifname "access-vlan2" oifname "policy-vlan2" accept comment "selector-handoff-forward--access-vlan2--access-to-selector-to-selector-to-policy--fabric"''
      ''iifname "policy-vlan2" oifname "access-vlan2" ct state established,related accept comment "selector-handoff-reverse--access-vlan2--selector-to-policy-to-access-to-selector--fabric"''
    ]
    && builtins.all (fragment: lib.hasInfix fragment policyNftables) [
      ''iifname "down-vlan2" oifname "upstream-vlan2" accept comment "allow-vlan2-to-wan"''
      ''iifname "upstream-vlan2" oifname "down-vlan2" ct state established,related accept comment "allow-vlan2-to-wan"''
    ]
    && builtins.all (fragment: lib.hasInfix fragment upstreamSelectorNftables) [
      ''iifname "policy-vlan2" oifname "core" accept comment "selector-handoff-forward--access-vlan2--selector-policy-uplink-to-selector-policy-uplink--wan"''
      ''iifname "core" oifname "policy-vlan2" ct state established,related accept comment "selector-handoff-reverse--access-vlan2--selector-policy-uplink-to-selector-policy-uplink--wan"''
    ]
    && hasStatelessRuleLine coreNftables [
      ''iifname "ens3"''
      ''oifname { "ppp0", "wan" }''
      ''accept comment "selector-handoff-forward--no-access--selector-policy-uplink-to-selector-transport--wan"''
    ]
    && hasStatelessRuleLine coreNftables [
      ''oifname { "ppp0", "wan" }''
      "ip saddr {"
      "192.168.1.0/24"
      "masquerade"
    ];

  hasVlan2PppoeBootPath =
    let
      pppService = (servicesFor "core")."pppd-s88-pppoe-client-wan" or { };
      starterService = (servicesFor "core")."s88-start-s88-pppoe-client-wan" or { };
      starterTimer =
        config.containers.core.config.systemd.timers."s88-start-s88-pppoe-client-wan" or { };
      pppPreStart = pppService.preStart or "";
      starterExec = toString (starterService.serviceConfig.ExecStart or "");
    in
    builtins.all (fragment: lib.hasInfix fragment pppPreStart) [
      "nic-br-wan6"
      "ifname ppp0"
      "defaultroute"
      "persist"
      "maxfail 0"
      "+ipv6"
      "defaultroute6"
      "mtu 1492"
      "mru 1492"
    ]
    && (pppService.serviceConfig.Restart or null) == "always"
    && (pppService.serviceConfig.RestartSec or null) == 5
    && (starterService.wantedBy or [ ]) == [ "multi-user.target" ]
    && lib.hasInfix "start pppd-s88-pppoe-client-wan.service" starterExec
    && (starterTimer.wantedBy or [ ]) == [ "timers.target" ]
    && (starterTimer.timerConfig.OnBootSec or null) == "10s"
    && (starterTimer.timerConfig.Unit or null) == "s88-start-s88-pppoe-client-wan.service";

  hasRendererNativePppoeMssClamp =
    hasStatelessRuleLine coreNftables [
      ''oifname { "ppp0", "wan" }''
      "tcp flags syn"
      "tcp option maxseg size set rt mtu"
    ];

  hasVlan2AdvertisedPppoePathMtu =
    let
      generator = (servicesFor "access-vlan2")."radvd-generate-lan2" or { };
      postStart = generator.postStart or "";
    in
    builtins.all (fragment: lib.hasInfix fragment postStart) [
      "AdvLinkMTU"
      "1492"
      "radvd --configtest"
    ];

  hasCoreDnsRequesterRoutes =
    hasRoute "access-vlan2" "10-access-vlan2" "10.19.0.2/31" "10.10.0.1"
    && hasRoute
      "access-vlan2"
      "10-access-vlan2"
      "fd42:dead:beef:1900:0000:0000:0000:0002/127"
      "fd42:dead:beef:1000:0:0:0:1"
    && hasSourcePolicyRule "access-vlan2" "10-access-vlan2" "ipv4" "${vlan2Dns.ipv4}/32"
    && hasSourcePolicyRule "access-vlan2" "10-access-vlan2" "ipv6" "${vlan2Dns.ipv6}/128"
    && hasRoute "access-vlan7" "10-access-vlan7" "10.19.0.3/32" "10.10.0.5"
    && hasRoute
      "access-vlan7"
      "10-access-vlan7"
      "fd42:dead:beef:1900:0000:0000:0000:0003/128"
      "fd42:dead:beef:1000:0:0:0:5"
    && hasSourcePolicyRule "access-vlan7" "10-access-vlan7" "ipv4" "${vlan7Dns.ipv4}/32"
    && hasSourcePolicyRule "access-vlan7" "10-access-vlan7" "ipv6" "${vlan7Dns.ipv6}/128";

  hasCoreDnsTraversalRules =
    let
      coreRules = dnsNftSurfaceFor "core";
      downstreamRules = dnsNftSurfaceFor "downstream-selector";
      policyRules = dnsNftSurfaceFor "policy";
      upstreamRules = dnsNftSurfaceFor "upstream-selector";
    in
    lib.hasInfix "type filter hook output priority filter; policy accept;" coreRules
    && builtins.all (fragment: lib.hasInfix fragment downstreamRules) [
      "selector-handoff-forward-runtime-origin--access-vlan2"
      "selector-handoff-forward-runtime-origin--access-vlan7"
      "selector-handoff-reverse-runtime-origin--access-vlan2"
      "selector-handoff-reverse-runtime-origin--access-vlan7"
    ]
    && builtins.all (fragment: lib.hasInfix fragment policyRules) [
      ''iifname "down-vlan2" oifname "upstream-vlan2" accept comment "allow-vlan2-to-wan"''
      ''iifname "downstr-vlan7" oifname "upstream-vlan7" accept comment "allow-vlan7-to-wan"''
    ]
    && builtins.all (fragment: lib.hasInfix fragment upstreamRules) [
      "selector-handoff-forward--access-vlan2--selector-policy-uplink-to-selector-policy-uplink--wan"
      "selector-handoff-forward--access-vlan7--selector-policy-uplink-to-selector-policy-uplink--wan"
      "selector-handoff-reverse--access-vlan2--selector-policy-uplink-to-selector-policy-uplink--wan"
      "selector-handoff-reverse--access-vlan7--selector-policy-uplink-to-selector-policy-uplink--wan"
    ];

  hasCoreDnsPathReconciliation =
    let
      service = (servicesFor "policy").s-router-prod-core-dns-path-reconcile or { };
      timer = config.containers.policy.config.systemd.timers.s-router-prod-core-dns-path-reconcile or { };
      script = service.script or "";
    in
    builtins.all (fragment: lib.hasInfix fragment script) [
      ''route del table "$table" "$prefix"''
      "${dnsResolver.ipv4}/32"
      "${dnsResolver.ipv4}/31"
      "${dnsResolver.ipv6}/128"
      "${dnsResolver.ipv6}/127"
      "down-vlan2 1004 upstream-vlan2"
      "downstr-vlan7 1006 upstream-vlan7"
    ]
    && (service.serviceConfig.Type or null) == "oneshot"
    && (timer.timerConfig.OnBootSec or null) == "1s"
    && (timer.timerConfig.OnUnitActiveSec or null) == "5s";

  hasVlan3ToVlan2DnsPath =
    let
      downstreamRules = dnsNftSurfaceFor "downstream-selector";
      policyRules = dnsNftSurfaceFor "policy";
      accessVlan2Input = dnsNftSurfaceFor "access-vlan2";
      accessVlan3Rules = dnsNftSurfaceFor "access-vlan3";
    in
    hasSourcePolicyRule "access-vlan3" "10-access-vlan3" "ipv4" "${vlan3Dns.ipv4}/32"
    && hasSourcePolicyRule "access-vlan3" "10-access-vlan3" "ipv6" "${vlan3Dns.ipv6}/128"
    && hasTableRoute
      "access-vlan3"
      "10-access-vlan3"
      "192.168.1.0/24"
      "10.10.0.3"
      1002
    && hasTableRoute
      "access-vlan3"
      "10-access-vlan3"
      "fd42:0001:0000:0000:0000:0000:0000:0000/64"
      "fd42:dead:beef:1000:0:0:0:3"
      1002
    && builtins.all
      (protocol:
        hasStatelessRuleLine downstreamRules [
          ''iifname "policy-vlan2"''
          ''oifname "access-vlan2"''
          "meta l4proto ${protocol}"
          "${protocol} dport { 53 }"
          ''accept comment "allow-vlan3-dns-to-vlan2-dns"''
        ])
      [
        "udp"
        "tcp"
      ]
    && builtins.all
      (spec:
        hasStatelessRuleLine policyRules [
          ''iifname "down-vlan3"''
          ''oifname "down-vlan2"''
          "${spec.family} saddr ${spec.source}"
          "meta l4proto ${spec.protocol}"
          "${spec.protocol} dport { 53 }"
          ''accept comment "allow-vlan3-dns-to-vlan2-dns"''
        ])
      [
        {
          family = "ip";
          source = vlan3Dns.ipv4;
          protocol = "udp";
        }
        {
          family = "ip";
          source = vlan3Dns.ipv4;
          protocol = "tcp";
        }
        {
          family = "ip6";
          source = vlan3Dns.ipv6;
          protocol = "udp";
        }
        {
          family = "ip6";
          source = vlan3Dns.ipv6;
          protocol = "tcp";
        }
      ]
    && lib.hasInfix "ct state established,related accept" downstreamRules
    && builtins.all (fragment: lib.hasInfix fragment accessVlan2Input) [
      "ip daddr ${vlan2Dns.ipv4} udp dport 53"
      "ip daddr ${vlan2Dns.ipv4} tcp dport 53"
      "ip6 daddr ${vlan2Dns.ipv6} udp dport 53"
      "ip6 daddr ${vlan2Dns.ipv6} tcp dport 53"
    ]
    && lib.hasInfix "type filter hook output priority filter; policy accept;" accessVlan3Rules;

  hasVlan2ToVlan3DnsPath =
    let
      downstreamRules = dnsNftSurfaceFor "downstream-selector";
      policyRules = dnsNftSurfaceFor "policy";
      accessVlan3Input = dnsNftSurfaceFor "access-vlan3";
    in
    hasSourcePolicyRule "access-vlan2" "10-access-vlan2" "ipv4" "${vlan2Dns.ipv4}/32"
    && hasSourcePolicyRule "access-vlan2" "10-access-vlan2" "ipv6" "${vlan2Dns.ipv6}/128"
    && hasTableRoute "access-vlan2" "10-access-vlan2" "0.0.0.0/0" "10.10.0.1" 1002
    && hasTableRoute
      "access-vlan2"
      "10-access-vlan2"
      "::/0"
      "fd42:dead:beef:1000:0:0:0:1"
      1002
    && builtins.all
      (spec:
        hasStatelessRuleLine policyRules [
          ''iifname "down-vlan2"''
          ''oifname "down-vlan3"''
          "${spec.family} saddr ${spec.source}"
          "meta l4proto ${spec.protocol}"
          "${spec.protocol} dport { 53 }"
          ''accept comment "allow-vlan2-dns-to-vlan3-dns"''
        ])
      [
        {
          family = "ip";
          source = vlan2Dns.ipv4;
          protocol = "udp";
        }
        {
          family = "ip";
          source = vlan2Dns.ipv4;
          protocol = "tcp";
        }
        {
          family = "ip6";
          source = vlan2Dns.ipv6;
          protocol = "udp";
        }
        {
          family = "ip6";
          source = vlan2Dns.ipv6;
          protocol = "tcp";
        }
      ]
    && builtins.all
      (protocol:
        hasStatelessRuleLine downstreamRules [
          ''iifname "policy-vlan3"''
          ''oifname "access-vlan3"''
          "meta l4proto ${protocol}"
          "${protocol} dport { 53 }"
          ''accept comment "allow-vlan2-dns-to-vlan3-dns"''
        ])
      [
        "udp"
        "tcp"
      ]
    && builtins.all (fragment: lib.hasInfix fragment accessVlan3Input) [
      "ip daddr ${vlan3Dns.ipv4} udp dport 53"
      "ip daddr ${vlan3Dns.ipv4} tcp dport 53"
      "ip6 daddr ${vlan3Dns.ipv6} udp dport 53"
      "ip6 daddr ${vlan3Dns.ipv6} tcp dport 53"
    ]
    && lib.hasInfix "ct state established,related accept" policyRules;

  hasRendererNativeNebulaRoutes =
    hasRoute "core" "10-ens3" "192.168.3.10/32" "10.10.0.7"
    && hasRoute "upstream-selector" "10-policy-vlan3" "192.168.3.10/32" "10.10.0.16"
    && hasRoute "policy" "10-down-vlan3" "192.168.3.10/32" "10.10.0.10"
    && hasRoute "downstream-selector" "10-access-vlan3" "192.168.3.10/32" "10.10.0.2"
    && hasRoute "access-vlan3" "10-access-vlan3" "10.19.0.3/32" "10.10.0.3"
    && hasRoute "downstream-selector" "10-policy-vlan3" "10.19.0.3/32" "10.10.0.11"
    && hasRoute "policy" "10-upstream-vlan3" "10.19.0.3/32" "10.10.0.17"
    && hasRoute "upstream-selector" "10-core" "10.19.0.3/32" "10.10.0.6";

  hasNoVlan2Vlan3MainTableOverride =
    !(builtins.any
      (rule:
        (rule.Family or null) == "ipv4"
        && (rule.IncomingInterface or null) == "access-vlan3"
        && (rule.Priority or null) == 900
        && (rule.Table or null) == 254
        && (rule.To or null) == "192.168.1.0/24")
      (
        config.containers.downstream-selector.config.systemd.network.networks."10-access-vlan3".routingPolicyRules or [ ]
      ));

  hasRendererNativeVlan3Fallback =
    let
      downstreamNetworks = config.containers.downstream-selector.config.systemd.network.networks;
    in
    builtins.any
      (rule:
        (rule.Family or null) == "ipv4"
        && (rule.From or null) == "192.168.3.0/24"
        && (rule.IncomingInterface or null) == "access-vlan3"
        && (rule.Priority or null) == 11002
        && (rule.Table or null) == 254
        && (rule.SuppressPrefixLength or null) == 0)
      (downstreamNetworks."10-access-vlan3".routingPolicyRules or [ ])
    && builtins.any
      (route:
        (route.Destination or null) == "192.168.1.0/24"
        && (route.Gateway or null) == "10.10.0.0"
        && (route.Table or 254) == 254)
      (downstreamNetworks."10-access-vlan2".routes or [ ]);

  hasRendererNativeVlan2ManagementPolicySelector =
    builtins.any
      (rule:
        (rule.Family or null) == "ipv4"
        && (rule.From or null) == "192.168.1.0/24"
        && (rule.To or null) == "192.168.3.0/24"
        && (rule.IncomingInterface or null) == "access-vlan2"
        && (rule.Priority or null) == 1000
        && (rule.Table or null) == 1004)
      (
        config.containers.downstream-selector.config.systemd.network.networks."10-access-vlan2".routingPolicyRules or [ ]
      );

  hasRendererNativeVlan2NebulaIcmp =
    lib.hasInfix
      ''iifname "policy-vlan3" oifname "access-vlan3" meta nfproto ipv4 ip protocol icmp accept comment "allow-vlan2-to-s-nebula-container-icmp"''
      downstreamSelectorNftables
    && lib.hasInfix
      ''iifname "access-vlan3" oifname "lan3" ip saddr 192.168.1.0/24 meta nfproto ipv4 ip protocol icmp accept comment "allow-vlan2-to-s-nebula-container-icmp"''
      accessVlan3Nftables
    && !(lib.hasInfix "s-router-prod-vlan2-nebula-icmp" downstreamSelectorNftables)
    && !(lib.hasInfix "s-router-prod-vlan2-nebula-icmp" accessVlan3Nftables);

  hasTemporaryVlan2HostManagement =
    let
      lan2Network = config.systemd.network.networks."50-lan2";
    in
    (lan2Network.networkConfig.DHCP or null) == "ipv4"
    && (lan2Network.dhcpV4Config.UseDNS or null) == false;
in
{
  assertions = [
    {
      assertion = config.virtualisation.qemu.networkingOptions == expectedQemuNetworkingOptions;
      message = ''
        s-router-prod must keep the legacy VM NIC contract:
          eth0 -> vmbr4, MAC 52:54:00:12:34:56
          eth1 -> vmbr1, MAC 52:54:00:12:34:57
      '';
    }
    {
      assertion = config.networking.useNetworkd;
      message = ''
        s-router-prod must be interpreted as a rendered router host.

        The network-* renderer must enable systemd-networkd for this host when it
        emits host bridges and container hostBridge attachments. Do not add a
        local networking.useNetworkd workaround in s-router-prod/default.nix.
      '';
    }
    {
      assertion = config.systemd.network.enable;
      message = ''
        s-router-prod rendered host networking must be managed by systemd-networkd.

        This is required for the generated LAN/WAN/transit bridges to exist before
        the containers start.
      '';
    }
    {
      assertion = config.networking.useDHCP == false;
      message = ''
        s-router-prod must not use the legacy global DHCP generator.

        Host interface behavior must come from prod-network/current/inventory.nix
        through the network-* render pipeline.
      '';
    }
    {
      assertion = builtins.elem "br-lan-trunk" netdevBridgeNames;
      message = ''
        s-router-prod must render the legacy LAN handoff bridge br-lan-trunk from inventory.
      '';
    }
    {
      assertion = builtins.elem "br-wan6" netdevBridgeNames;
      message = ''
        s-router-prod must render the WAN PPPoE lower bridge br-wan6 from inventory.
      '';
    }
    {
      assertion =
        builtins.elem "lan2" netdevBridgeNames
        && builtins.elem "lan3" netdevBridgeNames
        && builtins.elem "lan7" netdevBridgeNames;
      message = ''
        s-router-prod must render the client VLAN bridges lan2, lan3, and lan7 from inventory.
      '';
    }
    {
      assertion = hasExpectedContainers;
      message = ''
        s-router-prod must render exactly the production router roles from intent/inventory.

        The external ISP peer is a non-rendered model peer for PPPoE validation and
        must not become a local production container.
      '';
    }
    {
      assertion = builtins.elem "br-wan6" coreExtraVethBridges;
      message = ''
        s-router-prod core must attach its WAN side to the rendered br-wan6 handoff.
      '';
    }
    {
      assertion =
        config.sops.secrets ? pppoe-username
        && config.sops.secrets ? pppoe-password
        && config.sops.secrets ? s-router-prod-vlan2-reservations-json
        && config.sops.secrets ? s-router-prod-vlan2-reservation-names-json
        && config.sops.secrets ? s-router-prod-vlan3-reservations-json;
      message = ''
        s-router-prod must keep PPPoE credentials and protected VLAN 2/VLAN 3
        reservation sources wired as runtime secrets, not rendered model data.
      '';
    }
    {
      assertion =
        (config._module.args.sRouterProdModelSource.intentPath or null)
        == "${outPath}/prod-network/current/intent.nix"
        && (config._module.args.sRouterProdModelSource.inventoryPath or null)
        == "${outPath}/prod-network/current/inventory.nix";
      message = ''
        s-router-prod must consume the production intent.nix and inventory.nix directly.
      '';
    }
    {
      assertion =
        hasVlan2InternetRoutes
        && hasVlan2InternetFirewallAndNat
        && hasVlan2PppoeBootPath
        && hasRendererNativePppoeMssClamp
        && hasVlan2AdvertisedPppoePathMtu;
      message = ''
        s-router-prod VLAN 2 must retain its complete Internet path: source
        selection and default routes through access, downstream, policy,
        upstream, and core; stateful forwarding on every hop; masquerade of
        192.168.1.0/24 to ppp0; the boot-triggered persistent PPPoE client;
        renderer-native IPv4/IPv6 TCP MSS clamping; and an IPv6 router
        advertisement matching the 1492-byte PPPoE path MTU.
      '';
    }
    {
      assertion =
        unboundForwardersFor "access-vlan2" == expectedDnsForwarders
        && unboundForwardersFor "access-vlan7" == expectedDnsForwarders;
      message = ''
        s-router-prod VLAN 2 and VLAN 7 access resolvers must forward only to the
        core recursive resolver service over its internal IPv4 and IPv6
        endpoints.
      '';
    }
    {
      assertion =
        hasCoreDnsIntent
        && hasCoreRecursiveDns
        && hasCoreDnsInputRules
        && hasCoreDnsRequesterRoutes
        && hasCoreDnsTraversalRules
        && hasCoreDnsPathReconciliation
        && hasDnsEgressRules "access-vlan2"
        && hasDnsEgressRules "access-vlan7";
      message = ''
        s-router-prod must preserve the address-free access-dns -> core-dns
        target intent and materialize its temporary inventory projection with
        native dual-stack source policy, routes, firewall traversal, recursive
        core resolver isolation, and no invented public core forwarders. Until
        the network-* service-route closure stops leaking equal-prefix core
        routes across tenant tables, the explicit reconciliation override must
        keep VLAN 2 and VLAN 7 on their relation-bound upstream lanes.
      '';
    }
    {
      assertion =
        hasLocalDnsSharingIntent
        && hasVlan3LocalSharingDns
        && hasVlan2LocalOnlyPeerAcl
        && hasVlan3ToVlan2DnsPath
        && hasVlan2ToVlan3DnsPath;
      message = ''
        s-router-prod VLAN 3 DNS must resolve its own local data and VLAN 2's
        Kea-backed lan. data over the renderer-native access-to-access path.
        VLAN 2 DNS must query VLAN 3 for VLAN 3-owned local data instead of
        duplicating it. Every other namespace must terminate locally, and both
        peer directions must apply refuse_non_local so neither can borrow the
        other's recursion.
      '';
    }
    {
      assertion = hasNativeProtectedReservations;
      message = ''
        s-router-prod VLAN 2 and VLAN 3 must materialize their protected runtime
        reservation sets through the renderer-native source contract. No local
        post-render Kea reservation rewrite may remain.
      '';
    }
    {
      assertion = hasVlan2RuntimeLocalDns;
      message = ''
        s-router-prod must publish VLAN 2 runtime reservation hostnames through
        an Unbound lan. local-zone without leaking the private hostname source
        into inventory, flake eval output, or the Nix store. VLAN 3-owned names
        must not be duplicated there: the exact protected namespace must be
        forwarded to VLAN 3 Unbound without recursive fallback. The protected
        local publisher must preserve intentional multi-address hostnames that
        the native unique-name publication contract cannot represent.
      '';
    }
    {
      assertion = hasNativeKeaLeaseState;
      message = ''
        s-router-prod Kea lease databases must consume the inventory-owned
        /var/lib/kea/<vlan>.leases bindings with renderer-owned StateDirectory=kea.

        No host-profile post-render lease-path rewrite may remain.
      '';
    }
    {
      assertion = hasNebulaPublicIngressRules && hasRendererNativeNebulaRoutes;
      message = ''
        s-router-prod must receive scoped Nebula TCP/UDP 4242 DNAT, SNAT,
        forwarding, and dedicated VLAN 3 forward/return routes from the
        upstream CPM/renderer chain.
      '';
    }
    {
      assertion =
        hasRendererNativeIpv6Routes
        && hasNoExactTenantIpv6RouteCompatibility;
      message = ''
        s-router-prod must receive exact slot-derived tenant IPv6 routes from
        the renderer, without local s-router-prod-ipv6-routes compatibility
        services.
      '';
    }
    {
      assertion = hasIpv6CompatibilityGlue;
      message = ''
        s-router-prod must retain DHCPv6-PD acquisition and scoped Nebula IPv4/
        IPv6 ingress glue until those behaviors are modeled by the renderer.
      '';
    }
    {
      assertion =
        hasStatefulVlan3Return
        && hasNoVlan2Vlan3MainTableOverride
        && hasRendererNativeVlan3Fallback
        && hasRendererNativeVlan2ManagementPolicySelector
        && hasRendererNativeVlan2NebulaIcmp
        && hasTemporaryVlan2HostManagement;
      message = ''
        s-router-prod VLAN 3 to VLAN 2 traffic must remain limited to
        established/related return traffic. VLAN 2 management traffic to VLAN 3
        must use the renderer-native priority-1000 policy selector and native
        scoped ICMP handoffs, without the old local nftables additions. The
        s-router-prod lan2 host bridge must still acquire its management IPv4
        address using DHCP without replacing host DNS. Do not restore either
        old priority-900 override.
      '';
    }
  ];
}
