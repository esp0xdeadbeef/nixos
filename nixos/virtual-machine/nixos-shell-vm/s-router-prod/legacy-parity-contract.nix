{ config, lib, outPath, ... }:

let
  dnsRuntime = import "${outPath}/prod-network/s-router-prod/dns-runtime-addresses.nix";
  prodIntent = import "${outPath}/prod-network/s-router-prod/intent.nix";
  prodSite = prodIntent.esp0xdeadbeef.site-a;
  dnsResolver = dnsRuntime.resolver;
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
      "s88-delegated-prefix-policy-route-down-vlan3-1005"
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
    dnsResolver.ipv4
    dnsResolver.ipv6
  ];

  unboundForwardersFor =
    containerName:
    let
      settings = config.containers.${containerName}.config.services.unbound.settings or { };
      forwardZones = settings."forward-zone" or [ ];
    in
    lib.unique (lib.flatten (map (zone: zone."forward-addr" or [ ]) forwardZones));

  unboundForwardZonesFor =
    containerName:
      config.containers.${containerName}.config.services.unbound.settings."forward-zone" or [ ];

  unboundServerFor =
    containerName:
      config.containers.${containerName}.config.services.unbound.settings.server or { };

  hasVlan2RuntimeLocalDns =
    let
      server = unboundServerFor "access-vlan2";
    in
    builtins.elem "lan. static" (server.local-zone or [ ])
    && builtins.elem "1.168.192.in-addr.arpa. static" (server.local-zone or [ ])
    && builtins.elem "/run/unbound/s-router-prod-vlan2-local.conf" (server.include or [ ])
    && builtins.elem ''"s-nebula-container.lan. IN A 192.168.3.10"'' (server."local-data" or [ ])
    && builtins.elem
      ''"s-nebula-container.lan. IN AAAA fd42:dead:beef:3::1337:dead:beef"''
      (server."local-data" or [ ])
    && builtins.hasAttr "gen-s-router-prod-vlan2-unbound-local-data"
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
      ". static"
      "lan. transparent"
      "1.168.192.in-addr.arpa. transparent"
    ]
    && (server."access-control" or [ ]) == [
      "127.0.0.0/8 allow"
      "::1/128 allow"
      "${vlan3Dns.clientIpv4} allow"
      "${vlan3Dns.clientIpv6} allow"
      "${vlan2Dns.clientIpv4} refuse_non_local"
      "${vlan2Dns.clientIpv6} refuse_non_local"
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
      "ip6 saddr ${vlan2Dns.ipv6} ip6 daddr ${dnsResolver.ipv6} udp dport 53"
      "ip6 saddr ${vlan2Dns.ipv6} ip6 daddr ${dnsResolver.ipv6} tcp dport 53"
    ];

    access-vlan7 = [
      "ip saddr ${vlan7Dns.ipv4} ip daddr ${dnsResolver.ipv4} udp dport 53"
      "ip saddr ${vlan7Dns.ipv4} ip daddr ${dnsResolver.ipv4} tcp dport 53"
      "ip6 saddr ${vlan7Dns.ipv6} ip6 daddr ${dnsResolver.ipv6} udp dport 53"
      "ip6 saddr ${vlan7Dns.ipv6} ip6 daddr ${dnsResolver.ipv6} tcp dport 53"
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
      dnsResolver.ipv4
      dnsResolver.ipv6
    ]
    && (server."access-control" or [ ]) == [
      "127.0.0.0/8 allow"
      "::1/128 allow"
      "${vlan2Dns.clientIpv4} allow"
      "${vlan2Dns.clientIpv6} allow"
      "${vlan7Dns.ipv4}/32 allow"
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
      "ip6 daddr ${dnsResolver.ipv6} udp dport 53"
      "ip6 daddr ${dnsResolver.ipv6} tcp dport 53"
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
      desiredRelation = desiredLocalDnsIntent.relation;
    in
    activeRelation.priority < activeDnsRelationsById.deny-vlan3-to-vlan2.priority
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

  hasVlan3SecretReservation =
    let
      postHooks = execStartPostList (
        (keaGenServiceFor "access-vlan3" "vlan3").serviceConfig.ExecStartPost or null
      );
    in
    config.sops.secrets ? s-nebula-container-mac
    && builtins.any
      (hook: lib.hasInfix "apply-s-router-prod-vlan3-kea-reservation" (toString hook))
      postHooks;

  coreNftables = config.containers.core.config.networking.nftables.ruleset;
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

  hasTemporaryVlan2ManagementPolicySelector =
    builtins.any
      (rule:
        (rule.Family or null) == "ipv4"
        && (rule.From or null) == "192.168.1.0/24"
        && (rule.To or null) == "192.168.3.0/24"
        && (rule.IncomingInterface or null) == "access-vlan2"
        && (rule.Priority or null) == 900
        && (rule.Table or null) == 1004)
      (
        config.containers.downstream-selector.config.systemd.network.networks."10-access-vlan2".routingPolicyRules or [ ]
      );

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

        Host interface behavior must come from prod-network/s-router-prod/inventory.nix
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
        && config.sops.secrets ? s-nebula-container-mac;
      message = ''
        s-router-prod must keep PPPoE credentials, VLAN 2 reservations, and the
        s-nebula-container MAC wired as runtime secrets, not rendered model data.
      '';
    }
    {
      assertion =
        (config._module.args.sRouterProdModelSource.intentPath or null)
        == "${outPath}/prod-network/s-router-prod/intent.nix"
        && (config._module.args.sRouterProdModelSource.inventoryPath or null)
        == "${outPath}/prod-network/s-router-prod/inventory.nix";
      message = ''
        s-router-prod must consume the production intent.nix and inventory.nix directly.
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
        && hasDnsEgressRules "access-vlan2"
        && hasDnsEgressRules "access-vlan7";
      message = ''
        s-router-prod must preserve the address-free access-dns -> core-dns
        target intent and materialize its temporary inventory projection with
        native dual-stack source policy, routes, and firewall traversal. Only
        the core recursive resolver compatibility override may remain while
        recursiveDnsIntent documents the unfinished SMS row.
      '';
    }
    {
      assertion =
        hasLocalDnsSharingIntent
        && hasVlan3LocalSharingDns
        && hasVlan2LocalOnlyPeerAcl
        && hasVlan3ToVlan2DnsPath;
      message = ''
        s-router-prod VLAN 3 DNS must resolve its own local data and VLAN 2's
        Kea-backed lan. data over the renderer-native access-to-access path.
        Every other namespace must terminate locally, while VLAN 2 must apply
        refuse_non_local to VLAN 3 so the peer can never borrow recursion.
      '';
    }
    {
      assertion = hasVlan3SecretReservation;
      message = ''
        s-router-prod VLAN 3 must apply the s-nebula-container DHCP reservation
        from a runtime MAC secret instead of rendering the MAC into inventory or
        the Nix store.
      '';
    }
    {
      assertion = hasVlan2RuntimeLocalDns;
      message = ''
        s-router-prod must publish VLAN 2 runtime reservation hostnames through
        an Unbound lan. local-zone without leaking the private hostname source
        into inventory, flake eval output, or the Nix store.
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
        && hasTemporaryVlan2ManagementPolicySelector
        && hasTemporaryVlan2HostManagement;
      message = ''
        s-router-prod VLAN 3 to VLAN 2 traffic must remain limited to
        established/related return traffic. VLAN 2 management traffic to VLAN 3
        must temporarily select the existing policy table before renderer-native
        destination routing can bypass policy, and the s-router-prod lan2 host
        bridge must acquire its management IPv4 address using DHCP without
        replacing host DNS. Do not restore the old priority-900 main-table
        return-path override.
      '';
    }
  ];
}
