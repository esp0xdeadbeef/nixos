{ config, lib, sRouterProdRenderers, ... }:

let
  bundle = sRouterProdRenderers.canonicalBundle;
  controlPlane = bundle.network.data;
  site = controlPlane.control_plane_model.data.esp0xdeadbeef.site-a;
  relations = site.relations or [ ];
  validPaths = site.trafficPathValidation.validPaths or [ ];

  servicesByName = builtins.listToAttrs (
    map
      (service: {
        name = service.name;
        value = service;
      })
      (site.services or [ ])
  );

  externalNames =
    endpoint:
    lib.unique (
      (endpoint.uplinks or [ ])
      ++ lib.optional (endpoint ? name) endpoint.name
    );

  serviceTenants =
    serviceName:
    if builtins.hasAttr serviceName servicesByName then
      servicesByName.${serviceName}.providerTenants or [ ]
    else
      [ ];

  endpointCovers =
    authority: endpoint:
    if (authority.kind or null) == "external" && (endpoint.kind or null) == "external" then
      builtins.any
        (name: builtins.elem name (externalNames endpoint))
        (externalNames authority)
    else if (authority.kind or null) == "tenant" && (endpoint.kind or null) == "service" then
      builtins.elem authority.name (serviceTenants endpoint.name)
    else
      (authority.kind or null) == (endpoint.kind or null)
      && (authority.name or null) == (endpoint.name or null);

  packetMatches =
    packet: match:
    builtins.elem (match.proto or null) [
      "any"
      packet.protocol
    ]
    && builtins.elem (match.family or null) [
      "any"
      packet.family
    ]
    && (
      (match.dports or [ ]) == [ ]
      || builtins.elem packet.destinationPort (match.dports or [ ])
    );

  relationMatches =
    flow: relation:
    endpointCovers relation.from flow.source
    && endpointCovers relation.to flow.destination
    && builtins.any (packetMatches flow.packet) (relation.match or [ ]);

  relationPriority = relation: relation.priority or 65535;

  decide =
    flow:
    let
      matching = lib.sort
        (left: right: relationPriority left < relationPriority right)
        (builtins.filter (relationMatches flow) relations);
      winner = if matching == [ ] then null else builtins.head matching;
    in
    if winner == null then
      {
        action = "deny";
        reason = "default-deny";
        relation = null;
        relationId = null;
      }
    else
      {
        action = winner.action;
        reason = "relation";
        relation = winner;
        relationId = winner.id;
      };

  internetPathFor =
    vlan:
    [
      "access-${vlan}"
      "downstream-selector"
      "policy"
      "upstream-selector"
      "core"
    ];

  vlan2ToVlan3Path = [
    "access-vlan2"
    "downstream-selector"
    "policy"
    "downstream-selector"
    "access-vlan3"
  ];

  wanToVlan3Path = [
    "core"
    "upstream-selector"
    "policy"
    "downstream-selector"
    "access-vlan3"
  ];

  tenant = name: {
    kind = "tenant";
    inherit name;
  };

  external = name: {
    kind = "external";
    inherit name;
  };

  service = name: {
    kind = "service";
    inherit name;
  };

  packet =
    family: protocol: destinationPort:
    {
      inherit family protocol destinationPort;
    };

  positiveFlow =
    { id
    , source
    , destination
    , packet
    , expectedPath
    , expectedReturnBehavior
    ,
    }:
    {
      inherit
        id
        source
        destination
        packet
        expectedPath
        expectedReturnBehavior
        ;
      expectedAction = "allow";
    };

  deniedFlow =
    { id
    , source
    , destination
    , packet
    ,
    }:
    {
      inherit
        id
        source
        destination
        packet
        ;
      expectedAction = "deny";
      expectedPath = null;
      expectedReturnBehavior = null;
    };

  internetFlowsFor =
    vlan:
    map
      (family:
      positiveFlow {
        id = "${vlan}-${family}-internet";
        source = tenant vlan;
        destination = external "wan";
        packet = packet family "tcp" 443;
        expectedPath = internetPathFor vlan;
        expectedReturnBehavior = "symmetric";
      })
      [
        "ipv4"
        "ipv6"
      ];

  nebulaFlowsFrom =
    sourceName: source: expectedPath: expectedReturnBehavior:
    lib.flatten (
      map
        (family:
        map
          (protocol:
          positiveFlow {
            id = "${sourceName}-${family}-${protocol}-nebula";
            inherit source expectedPath expectedReturnBehavior;
            destination = service "s-nebula-container";
            packet = packet family protocol 4242;
          })
          [
            "udp"
            "tcp"
          ])
        [
          "ipv4"
          "ipv6"
        ]
    );

  deniedTenantFlows =
    sourceName: destinationNames:
    lib.flatten (
      map
        (destinationName:
        map
          (family:
          deniedFlow {
            id = "${sourceName}-${family}-to-${destinationName}";
            source = tenant sourceName;
            destination =
              if destinationName == "wan" then
                external destinationName
              else
                tenant destinationName;
            packet = packet family "tcp" 443;
          })
          [
            "ipv4"
            "ipv6"
          ])
        destinationNames
    );

  flows =
    internetFlowsFor "vlan2"
    ++ internetFlowsFor "vlan7"
    ++ nebulaFlowsFrom "wan" (external "wan") wanToVlan3Path "stateful-return"
    ++ nebulaFlowsFrom "vlan2" (tenant "vlan2") vlan2ToVlan3Path "symmetric"
    ++ deniedTenantFlows "vlan3" [
      "wan"
      "vlan2"
      "vlan7"
    ]
    ++ deniedTenantFlows "vlan7" [
      "vlan2"
      "vlan3"
    ];

  pathMatches =
    flow: decision:
    flow.expectedPath == null
    || builtins.any
      (path:
      path.relationId == decision.relationId
      && path.action == "allow"
      && path.nodePath == flow.expectedPath)
      validPaths;

  returnBehaviorMatches =
    flow: decision:
    flow.expectedReturnBehavior == null
    || (decision.relation.returnBehavior or null) == flow.expectedReturnBehavior;

  evaluateFlow =
    flow:
    let
      decision = decide flow;
      passed =
        decision.action == flow.expectedAction
        && pathMatches flow decision
        && returnBehaviorMatches flow decision;
    in
    {
      inherit (flow) id expectedAction expectedPath expectedReturnBehavior;
      inherit decision passed;
    };

  results = map evaluateFlow flows;
  failures = builtins.filter (result: !result.passed) results;

  supportedEndpointKinds = [
    "external"
    "service"
    "tenant"
  ];

  hasSupportedRelationShape =
    relation:
    builtins.elem (relation.action or null) [
      "allow"
      "deny"
    ]
    && builtins.elem (relation.from.kind or null) supportedEndpointKinds
    && builtins.elem (relation.to.kind or null) supportedEndpointKinds
    && (relation.match or [ ]) != [ ];

  failureText =
    result:
    "${result.id}: expected ${result.expectedAction}, got ${result.decision.action} via ${
      result.decision.relationId or result.decision.reason
    }";

  networkUnitsFor =
    containerName:
    config.containers.${containerName}.config.systemd.network.networks;

  annotatedNetworkEntries =
    field: containerName:
    let
      units = networkUnitsFor containerName;
    in
    lib.flatten (
      map
        (unitName:
        map
          (entry:
          entry
          // {
            assertionUnit = unitName;
          })
          (units.${unitName}.${field} or [ ]))
        (builtins.attrNames units)
    );

  routesFor = annotatedNetworkEntries "routes";
  routingPolicyRulesFor = annotatedNetworkEntries "routingPolicyRules";

  sourcePolicyInternetStage =
    { containerName
    , incomingInterface
    , sourcePrefix
    ,
    }:
    let
      matchingRules = builtins.filter
        (rule:
          (rule.Family or null) == "ipv4"
          && (rule.From or null) == sourcePrefix
          && (rule.IncomingInterface or null) == incomingInterface
          && (rule.To or null) == null
          && (rule.Table or 254) != 254
          && (rule.SuppressPrefixLength or null) == null)
        (routingPolicyRulesFor containerName);
      matchingDefaultRoutes = builtins.filter
        (route:
          (route.Table or null) != null
          && (route.Destination or null) == "0.0.0.0/0"
          && (route.Gateway or null) != null)
        (routesFor containerName);
      defaultRouteTables =
        lib.unique (map (route: route.Table) matchingDefaultRoutes);
      candidateRules = lib.sort
        (left: right: left.Priority < right.Priority)
        (builtins.filter
          (rule:
            builtins.elem rule.Table defaultRouteTables
            && (rule.Priority or null) == rule.Table)
          matchingRules);
      winningPriority =
        if candidateRules == [ ] then
          null
        else
          (builtins.head candidateRules).Priority;
      selectedRules = builtins.filter
        (rule:
          winningPriority != null
          && rule.Priority == winningPriority)
        candidateRules;
      candidateTables = lib.unique (map (rule: rule.Table) selectedRules);
      table =
        if builtins.length candidateTables == 1 then
          builtins.head candidateTables
        else
          null;
      defaultRoutes = builtins.filter
        (route: table != null && route.Table == table)
        matchingDefaultRoutes;
    in
    {
      inherit
        containerName
        defaultRoutes
        incomingInterface
        matchingRules
        selectedRules
        sourcePrefix
        table
        ;
      passed =
        table != null
        && selectedRules != [ ]
        && builtins.all
          (rule: (rule.Priority or null) == table)
          selectedRules
        && defaultRoutes != [ ];
    };

  internetStagesFor =
    { accessInterface
    , accessName
    , localInterface
    , policyDownInterface
    , sourcePrefix
    , upstreamPolicyInterface
    ,
    }:
    [
      (sourcePolicyInternetStage {
        containerName = accessName;
        incomingInterface = localInterface;
        inherit sourcePrefix;
      })
      (sourcePolicyInternetStage {
        containerName = "downstream-selector";
        incomingInterface = accessInterface;
        inherit sourcePrefix;
      })
      (sourcePolicyInternetStage {
        containerName = "policy";
        incomingInterface = policyDownInterface;
        inherit sourcePrefix;
      })
      (sourcePolicyInternetStage {
        containerName = "upstream-selector";
        incomingInterface = upstreamPolicyInterface;
        inherit sourcePrefix;
      })
    ];

  vlan2InternetStages = internetStagesFor {
    accessName = "access-vlan2";
    accessInterface = "access-vlan2";
    localInterface = "lan2";
    policyDownInterface = "down-vlan2";
    sourcePrefix = "192.168.1.0/24";
    upstreamPolicyInterface = "policy-vlan2";
  };

  vlan7InternetStages = internetStagesFor {
    accessName = "access-vlan7";
    accessInterface = "access-vlan7";
    localInterface = "lan7";
    policyDownInterface = "downstr-vlan7";
    sourcePrefix = "192.168.2.0/24";
    upstreamPolicyInterface = "policy";
  };

  hasCoreReturnRoute =
    sourcePrefix:
    builtins.any
      (route:
      (route.Destination or null) == sourcePrefix
      && (route.Gateway or null) != null)
      (routesFor "core");

  policyTableFor =
    stages:
    let
      policyStage = builtins.elemAt stages 2;
    in
    policyStage.table;

  nftablesFor =
    containerName:
    config.containers.${containerName}.config.networking.nftables.ruleset;

  ruleLines = ruleset: lib.splitString "\n" ruleset;

  lineMatches =
    fragments: line:
    builtins.all (fragment: lib.hasInfix fragment line) fragments;

  hasRuleLine =
    ruleset: fragments:
    builtins.any (lineMatches fragments) (ruleLines ruleset);

  statelessAcceptLinesFrom =
    ruleset: incomingInterface:
    builtins.filter
      (line:
      lineMatches
        [
          ''iifname "${incomingInterface}"''
          " accept"
        ]
        line
      && !(lib.hasInfix "ct state" line))
      (ruleLines ruleset);

  coreNftables = nftablesFor "core";
  accessVlan2Nftables = nftablesFor "access-vlan2";
  accessVlan3Nftables = nftablesFor "access-vlan3";
  accessVlan7Nftables = nftablesFor "access-vlan7";
  downstreamSelectorNftables = nftablesFor "downstream-selector";
  policyNftables = nftablesFor "policy";
  upstreamSelectorNftables = nftablesFor "upstream-selector";

  hasDefaultDropForwarding =
    ruleset:
    lib.hasInfix "type filter hook forward priority filter; policy drop;" ruleset;

  vlan7InternetFirewallAndNatChecks = {
    accessForward = hasRuleLine accessVlan7Nftables [
      ''iifname "lan7"''
      ''oifname "access-vlan7"''
      " accept"
    ];
    accessReturn = hasRuleLine accessVlan7Nftables [
      ''iifname "access-vlan7"''
      ''oifname "lan7"''
      "ct state established,related"
      " accept"
    ];
    downstreamForward = hasRuleLine downstreamSelectorNftables [
      ''iifname "access-vlan7"''
      ''oifname "policy-vlan7"''
      " accept"
    ];
    downstreamReturn = hasRuleLine downstreamSelectorNftables [
      ''iifname "policy-vlan7"''
      ''oifname "access-vlan7"''
      "ct state established,related"
      " accept"
    ];
    policyForward = hasRuleLine policyNftables [
      ''iifname "downstr-vlan7"''
      ''oifname "upstream-vlan7"''
      ''accept comment "allow-vlan7-to-wan"''
    ];
    policyReturn = hasRuleLine policyNftables [
      ''iifname "upstream-vlan7"''
      ''oifname "downstr-vlan7"''
      "ct state established,related"
      ''accept comment "allow-vlan7-to-wan"''
    ];
    upstreamForward = hasRuleLine upstreamSelectorNftables [
      ''iifname "policy"''
      ''oifname "core"''
      " accept"
    ];
    upstreamReturn = hasRuleLine upstreamSelectorNftables [
      ''iifname "core"''
      ''oifname "policy"''
      "ct state established,related"
      " accept"
    ];
    coreForward = hasRuleLine coreNftables [
      ''iifname "ens3"''
      "ppp0"
      " accept"
    ];
    coreReturn = hasRuleLine coreNftables [
      ''oifname "ens3"''
      "ppp0"
      "ct state established,related"
      " accept"
    ];
    coreNat = hasRuleLine coreNftables [
      "192.168.2.0/24"
      "ppp0"
      "masquerade"
    ];
  };

  hasVlan7InternetFirewallAndNat =
    builtins.all
      (passed: passed)
      (builtins.attrValues vlan7InternetFirewallAndNatChecks);

  failedVlan7FirewallAndNatChecks =
    builtins.attrNames (
      lib.filterAttrs
        (_: passed: !passed)
        vlan7InternetFirewallAndNatChecks
    );

  internetStageSummary =
    stages:
    map
      (stage: {
        inherit (stage)
          containerName
          incomingInterface
          passed
          table
          ;
        defaultRouteCount = builtins.length stage.defaultRoutes;
        selectedRuleCount = builtins.length stage.selectedRules;
      })
      stages;

  vlan7PolicyNewFlows =
    statelessAcceptLinesFrom policyNftables "downstr-vlan7";
  vlan7SelectorNewFlows =
    statelessAcceptLinesFrom downstreamSelectorNftables "access-vlan7";

  hasVlan7LateralIsolation =
    hasDefaultDropForwarding downstreamSelectorNftables
    && hasDefaultDropForwarding policyNftables
    && vlan7SelectorNewFlows != [ ]
    && builtins.all
      (line: lib.hasInfix ''oifname "policy-vlan7"'' line)
      vlan7SelectorNewFlows
    && vlan7PolicyNewFlows != [ ]
    && builtins.all
      (line:
        lib.hasInfix ''oifname "upstream-vlan7"'' line
        || lineMatches
          [
            ''oifname "downstr-vlan7"''
            ''accept comment "allow-vlan7-to-vlan7-dns"''
          ]
          line)
      vlan7PolicyNewFlows;

  vlan3PolicyNewFlows =
    statelessAcceptLinesFrom policyNftables "down-vlan3";
  vlan3SelectorNewFlows =
    statelessAcceptLinesFrom downstreamSelectorNftables "access-vlan3";

  hasVlan3Airgap =
    hasDefaultDropForwarding downstreamSelectorNftables
    && hasDefaultDropForwarding policyNftables
    && vlan3SelectorNewFlows != [ ]
    && builtins.all
      (line: lib.hasInfix ''oifname "policy-vlan3"'' line)
      vlan3SelectorNewFlows
    && vlan3PolicyNewFlows != [ ]
    && builtins.all
      (line:
        lineMatches
          [
            ''oifname "down-vlan2"''
            ''accept comment "allow-vlan3-dns-to-vlan2-dns"''
          ]
          line
        || lineMatches
          [
            ''oifname "down-vlan3"''
            ''accept comment "allow-vlan3-to-vlan3-dns"''
          ]
          line)
      vlan3PolicyNewFlows;

  hasVlan2NebulaRenderedPath =
    hasRuleLine policyNftables [
      ''iifname "down-vlan2"''
      ''oifname "down-vlan3"''
      ''accept comment "allow-vlan2-to-vlan3"''
    ]
    && hasRuleLine downstreamSelectorNftables [
      ''iifname "policy-vlan3"''
      ''oifname "access-vlan3"''
      ''accept comment "allow-vlan2-to-vlan3"''
    ]
    && hasRuleLine accessVlan3Nftables [
      ''iifname "access-vlan3"''
      ''oifname "lan3"''
      "ip saddr 192.168.1.0/24"
      ''accept comment "allow-vlan2-to-vlan3"''
    ]
    && hasRuleLine policyNftables [
      ''iifname "down-vlan3"''
      ''oifname "down-vlan2"''
      "ct state established,related"
      ''accept comment "allow-vlan2-to-vlan3"''
    ];

  hasWanNebulaRenderedPath =
    builtins.all
      (protocol:
        hasRuleLine upstreamSelectorNftables [
          ''iifname "core"''
          ''oifname "policy-vlan3"''
          "meta l4proto ${protocol}"
          "${protocol} dport"
          "4242"
          ''accept comment "allow-wan-to-s-nebula-container"''
        ]
        && hasRuleLine policyNftables [
          ''iifname "upstream-vlan3"''
          ''oifname "down-vlan3"''
          "meta l4proto ${protocol}"
          "${protocol} dport"
          "4242"
          ''accept comment "allow-wan-to-s-nebula-container"''
        ]
        && hasRuleLine downstreamSelectorNftables [
          ''iifname "policy-vlan3"''
          ''oifname "access-vlan3"''
          "meta l4proto ${protocol}"
          "${protocol} dport"
          "4242"
          ''accept comment "allow-wan-to-s-nebula-container"''
        ]
        && hasRuleLine accessVlan3Nftables [
          ''iifname "access-vlan3"''
          ''oifname "lan3"''
          "ip daddr 192.168.3.10"
          "meta l4proto ${protocol}"
          "${protocol} dport"
          "4242"
          ''accept comment "allow-wan-to-s-nebula-container"''
        ])
      [
        "udp"
        "tcp"
      ];
in
{
  _module.args.sRouterProdForwardingInvariantResults = results;

  assertions = [
    {
      assertion =
        (bundle.validation.valid or false)
        && (bundle.validation.artifactIdentity or null) == bundle.bundleIdentity;
      message = ''
        s-router-prod must consume a released, schema-validated canonical
        network-realization bundle whose validation identity matches the
        consumed bundle identity.
      '';
    }
    {
      assertion = builtins.all hasSupportedRelationShape relations;
      message = ''
        s-router-prod's static forwarding verifier encountered a relation shape
        it cannot evaluate fail-closed. Extend forwarding-invariants.nix before
        accepting this network-* pin set.
      '';
    }
    {
      assertion = (site.trafficPathValidation.invalidPathCount or 1) == 0;
      message = ''
        s-router-prod's canonical realization contains an invalid forwarding
        path. No renderer output may be accepted from this bundle.
      '';
    }
    {
      assertion = failures == [ ];
      message = ''
        s-router-prod's canonical forwarding matrix changed:
          ${lib.concatMapStringsSep "\n  " failureText failures}

        Required posture:
          - VLAN 2 and VLAN 7 retain dual-stack Internet egress.
          - WAN and VLAN 2 reach Nebula on VLAN 3 over UDP/TCP 4242.
          - VLAN 3 initiates no tenant or Internet traffic.
          - VLAN 7 cannot initiate traffic to VLAN 2 or VLAN 3.
          - Positive paths retain their canonical staged node path and
            stateful return behavior.
      '';
    }
    {
      assertion =
        builtins.all (stage: stage.passed) vlan2InternetStages
        && builtins.all (stage: stage.passed) vlan7InternetStages
        && hasCoreReturnRoute "192.168.1.0/24"
        && hasCoreReturnRoute "192.168.2.0/24"
        && policyTableFor vlan2InternetStages != policyTableFor vlan7InternetStages
        && hasVlan7InternetFirewallAndNat;
      message = ''
        s-router-prod's effective rendered dataplane no longer preserves the
        complete VLAN 2/VLAN 7 IPv4 Internet path. Each access, downstream,
        policy, and upstream hop must have one source-and-ingress-selected
        non-main table with a gateway-qualified default route; VLAN 2 and VLAN
        7 must use distinct policy tables; core must retain both return routes;
        every nftables handoff must be stateful; and VLAN 7 must remain in the
        core IPv4 masquerade set. The canonical dual-stack intent and existing
        delegated-prefix/PPPoE parity assertions cover the corresponding IPv6
        route lifecycle.

        Route stages:
          ${builtins.toJSON {
            vlan2 = internetStageSummary vlan2InternetStages;
            vlan7 = internetStageSummary vlan7InternetStages;
          }}
        Failed VLAN 7 nft/NAT checks:
          ${builtins.toJSON failedVlan7FirewallAndNatChecks}
      '';
    }
    {
      assertion = hasVlan7LateralIsolation && hasVlan3Airgap;
      message = ''
        s-router-prod's effective nftables output violated tenant isolation.
        VLAN 7 may create new flows only toward its policy/WAN lane and may not
        bypass policy toward VLAN 2 or VLAN 3. VLAN 3 must remain default-drop:
        its only new-flow exception is the explicitly source/port-scoped
        vlan3-dns -> vlan2-dns relation; WAN and VLAN 2 ingress may return only
        through established/related state.
      '';
    }
    {
      assertion = hasVlan2NebulaRenderedPath && hasWanNebulaRenderedPath;
      message = ''
        s-router-prod's effective nftables output no longer carries Nebula to
        VLAN 3. WAN ingress must retain exact UDP/TCP 4242 forwarding through
        upstream-selector, policy, downstream-selector, and access-vlan3.
        VLAN 2 must retain its policy-required relation-bound path to VLAN 3,
        including the second downstream-selector traversal and destination
        access handoff, with established/related return only.
      '';
    }
  ];
}
