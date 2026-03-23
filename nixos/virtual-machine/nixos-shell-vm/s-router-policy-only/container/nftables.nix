# ./container/nftables.nix
{
  config,
  lib,
  controlPlaneOut,
  ...
}:

let
  hostname = config.networking.hostName;
  inventory = import ../inventory.nix;

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  shortenIfName =
    name:
    if lib.stringLength name <= 15 then
      name
    else
      "if${builtins.substring 0 13 (builtins.hashString "sha256" name)}";

  relationPriority =
    relation:
    if relation ? priority then
      relation.priority
    else if relation ? source && relation.source ? priority then
      relation.source.priority
    else
      0;

  relationName =
    relation:
    if relation ? id then
      relation.id
    else if relation ? source && relation.source ? id then
      relation.source.id
    else if relation ? trafficType then
      "${relation.action}-${relation.trafficType}"
    else
      relation.action;

  sortRelations =
    relations:
    lib.sort (a: b: relationPriority a < relationPriority b) relations;

  containerNode =
    if inventory ? realization && inventory.realization ? nodes && lib.hasAttr hostname inventory.realization.nodes then
      inventory.realization.nodes.${hostname}
    else
      abort "container/nftables.nix: realization node '${hostname}' missing in inventory.nix";

  containerNodePorts =
    if containerNode ? ports && builtins.isAttrs containerNode.ports then
      containerNode.ports
    else
      abort "container/nftables.nix: realization node '${hostname}' is missing ports";

  containerLinks =
    lib.sort builtins.lessThan (map (p: containerNodePorts.${p}.link) (builtins.attrNames containerNodePorts));

  cpmModel = controlPlaneOut.control_plane_model or { };
  cpmData = cpmModel.data or { };

  rootEnterprise =
    if controlPlaneOut ? enterprise && builtins.isAttrs controlPlaneOut.enterprise then
      controlPlaneOut.enterprise
    else if cpmModel ? enterprise && builtins.isAttrs cpmModel.enterprise then
      cpmModel.enterprise
    else
      { };

  rootEndpointInventory =
    if controlPlaneOut ? endpointInventory
      && builtins.isAttrs controlPlaneOut.endpointInventory
      && controlPlaneOut.endpointInventory ? endpoints
      && builtins.isAttrs controlPlaneOut.endpointInventory.endpoints
    then
      controlPlaneOut.endpointInventory.endpoints
    else if cpmModel ? endpointInventory
      && builtins.isAttrs cpmModel.endpointInventory
      && cpmModel.endpointInventory ? endpoints
      && builtins.isAttrs cpmModel.endpointInventory.endpoints
    then
      cpmModel.endpointInventory.endpoints
    else
      { };

  flatRelations =
    if cpmModel ? relations && builtins.isList cpmModel.relations then
      cpmModel.relations
    else if controlPlaneOut ? relations && builtins.isList controlPlaneOut.relations then
      controlPlaneOut.relations
    else
      [ ];

  linkNamesForTarget =
    target:
    let
      interfaces = target.effectiveRuntimeRealization.interfaces or { };
    in
    lib.sort builtins.lessThan (
      lib.filter (x: x != null) (
        map (
          ifName:
          let
            iface = interfaces.${ifName};
            backingRef = iface.backingRef or { };
          in
          if (backingRef.kind or null) == "link" then backingRef.name else null
        ) (sortedAttrNames interfaces)
      )
    );

  siteCandidates =
    lib.concatMap (
      enterpriseName:
      let
        siteAttrs = cpmData.${enterpriseName};
      in
      map (
        siteName:
        let
          site = siteAttrs.${siteName};
          runtimeTargets = site.runtimeTargets or { };
          runtimeTargetNames = sortedAttrNames runtimeTargets;
          matchingPolicyTargets = lib.filter (
            targetName:
            let
              target = runtimeTargets.${targetName};
            in
            (target.role or null) == "policy"
            && builtins.toJSON (linkNamesForTarget target) == builtins.toJSON containerLinks
          ) runtimeTargetNames;
        in
        {
          inherit enterpriseName siteName site matchingPolicyTargets;
        }
      ) (sortedAttrNames siteAttrs)
    ) (sortedAttrNames cpmData);

  matchedSites = lib.filter (entry: entry.matchingPolicyTargets != [ ]) siteCandidates;

  selectedSite =
    if builtins.length matchedSites == 1 then
      builtins.elemAt matchedSites 0
    else if matchedSites == [ ] then
      abort ''
        container/nftables.nix: no policy runtime target matches container '${hostname}'
        containerLinks: ${builtins.toJSON containerLinks}
      ''
    else
      abort ''
        container/nftables.nix: multiple policy runtime targets match container '${hostname}'
        matches: ${builtins.toJSON (map (x: { inherit (x) enterpriseName siteName matchingPolicyTargets; }) matchedSites)}
      '';

  enterpriseRecord =
    if builtins.hasAttr selectedSite.enterpriseName rootEnterprise then
      rootEnterprise.${selectedSite.enterpriseName}
    else
      abort ''
        container/nftables.nix: enterprise '${selectedSite.enterpriseName}' missing
      '';

  siteTree =
    if enterpriseRecord ? site && builtins.isAttrs enterpriseRecord.site then
      enterpriseRecord.site
    else
      abort ''
        container/nftables.nix: enterprise '${selectedSite.enterpriseName}' missing site tree
      '';

  enterpriseSite =
    if builtins.hasAttr selectedSite.siteName siteTree then
      siteTree.${selectedSite.siteName}
    else
      abort ''
        container/nftables.nix: site '${selectedSite.siteName}' missing under enterprise '${selectedSite.enterpriseName}'
      '';

  communicationContract =
    if enterpriseSite ? communicationContract && builtins.isAttrs enterpriseSite.communicationContract then
      enterpriseSite.communicationContract
    else if selectedSite.site ? communicationContract && builtins.isAttrs selectedSite.site.communicationContract then
      selectedSite.site.communicationContract
    else
      { };

  trafficTypes =
    if communicationContract ? trafficTypes && builtins.isList communicationContract.trafficTypes then
      communicationContract.trafficTypes
    else
      [ ];

  contractRelations =
    if communicationContract ? allowedRelations && builtins.isList communicationContract.allowedRelations then
      sortRelations communicationContract.allowedRelations
    else
      [ ];

  trafficTypeByName = builtins.listToAttrs (map (tt: {
    name = tt.name;
    value = tt;
  }) trafficTypes);

  expandRelationMatch =
    relation:
    if relation ? match && builtins.isList relation.match then
      relation.match
    else if (relation.trafficType or "any") == "any" then
      [ { family = "any"; proto = "any"; dports = [ ]; } ]
    else if builtins.hasAttr relation.trafficType trafficTypeByName then
      trafficTypeByName.${relation.trafficType}.match or [ ]
    else
      abort ''
        container/nftables.nix: unknown trafficType '${relation.trafficType}'
        relation: ${builtins.toJSON relation}
      '';

  relations =
    map
      (relation: relation // { match = expandRelationMatch relation; })
      (if contractRelations != [ ] then contractRelations else sortRelations flatRelations);

  runtimeTargets = selectedSite.site.runtimeTargets or { };

  policyTargetName =
    if builtins.length selectedSite.matchingPolicyTargets == 1 then
      builtins.elemAt selectedSite.matchingPolicyTargets 0
    else
      abort ''
        container/nftables.nix: expected exactly one policy runtime target
        matches: ${builtins.toJSON selectedSite.matchingPolicyTargets}
      '';

  policyTarget = runtimeTargets.${policyTargetName};
  policyInterfaces = policyTarget.effectiveRuntimeRealization.interfaces or { };

  hasDefaultRoute =
    iface:
    let
      v4 = iface.routes.ipv4 or [ ];
      v6 = iface.routes.ipv6 or [ ];
    in
    lib.any (r: (r.dst or "") == "0.0.0.0/0") v4
    || lib.any (r: (r.dst or "") == "::/0") v6;

  policyLinkEntries = lib.filter
    (x: x.linkName != null)
    (map (
      ifName:
      let
        iface = policyInterfaces.${ifName};
        backingRef = iface.backingRef or { };
      in
      {
        runtimeIfName = ifName;
        renderedIfName = shortenIfName iface.renderedIfName;
        linkName =
          if (backingRef.kind or null) == "link" && (backingRef.name or "") != "" then
            backingRef.name
          else
            null;
        defaultRoute = hasDefaultRoute iface;
      }
    ) (sortedAttrNames policyInterfaces));

  linkToIf = builtins.listToAttrs (map (entry: {
    name = entry.linkName;
    value = entry.renderedIfName;
  }) policyLinkEntries);

  uplinkCandidates = lib.filter (entry: entry.defaultRoute) policyLinkEntries;

  uplinkIf =
    if builtins.length uplinkCandidates == 1 then
      (builtins.elemAt uplinkCandidates 0).renderedIfName
    else
      abort ''
        container/nftables.nix: expected exactly one uplink interface on policy target
        candidates: ${builtins.toJSON (map (x: { inherit (x) linkName renderedIfName; }) uplinkCandidates)}
      '';

  uniqueLinkForTarget =
    targetName:
    let
      target = runtimeTargets.${targetName} or (abort "container/nftables.nix: runtime target '${targetName}' missing");
      links = linkNamesForTarget target;
    in
    if builtins.length links == 1 then
      builtins.elemAt links 0
    else
      abort ''
        container/nftables.nix: expected exactly one policy-facing link for access target '${targetName}'
        links: ${builtins.toJSON links}
      '';

  attachments = selectedSite.site.attachments or [ ];

  tenantToIf = builtins.listToAttrs (map (
    attachment:
    let
      linkName = uniqueLinkForTarget attachment.unit;
      ifName =
        if builtins.hasAttr linkName linkToIf then
          linkToIf.${linkName}
        else
          abort ''
            container/nftables.nix: policy target missing interface for link '${linkName}'
            tenant: ${attachment.name}
            unit: ${attachment.unit}
          '';
    in
    {
      name = attachment.name;
      value = ifName;
    }
  ) attachments);

  siteOwnership =
    if enterpriseSite ? ownership && builtins.isAttrs enterpriseSite.ownership then
      enterpriseSite.ownership
    else if selectedSite.site ? ownership && builtins.isAttrs selectedSite.site.ownership then
      selectedSite.site.ownership
    else if cpmModel ? ownership && builtins.isAttrs cpmModel.ownership then
      cpmModel.ownership
    else if controlPlaneOut ? ownership && builtins.isAttrs controlPlaneOut.ownership then
      controlPlaneOut.ownership
    else
      { };

  ownershipEndpoints =
    if siteOwnership ? endpoints && builtins.isList siteOwnership.endpoints then
      siteOwnership.endpoints
    else
      [ ];

  providerToTenant = builtins.listToAttrs (map (
    endpoint:
    {
      name = endpoint.name;
      value = endpoint.tenant;
    }
  ) (lib.filter (endpoint: endpoint ? name && endpoint ? tenant) ownershipEndpoints));

  serviceDefinitions =
    if communicationContract ? services && builtins.isList communicationContract.services then
      communicationContract.services
    else
      [ ];

  serviceData = builtins.listToAttrs (map (
    service:
    let
      providers = service.providers or [ ];
      tenants = lib.unique (map (
        provider:
        if builtins.hasAttr provider providerToTenant then
          providerToTenant.${provider}
        else
          abort ''
            container/nftables.nix: provider '${provider}' has no tenant ownership
            service: ${service.name}
          ''
      ) providers);
      interfaces = lib.unique (map (
        tenant:
        if builtins.hasAttr tenant tenantToIf then
          tenantToIf.${tenant}
        else
          abort ''
            container/nftables.nix: tenant '${tenant}' has no policy interface
            service: ${service.name}
          ''
      ) tenants);
    in
    {
      name = service.name;
      value = {
        inherit providers tenants interfaces;
        ipv4 = lib.concatMap (provider: (rootEndpointInventory.${provider}.ipv4 or [ ])) providers;
        ipv6 = lib.concatMap (provider: (rootEndpointInventory.${provider}.ipv6 or [ ])) providers;
      };
    }
  ) serviceDefinitions);

  fmtQuotedSet =
    xs:
    if builtins.length xs == 1 then
      "\"${builtins.elemAt xs 0}\""
    else
      "{ ${lib.concatMapStringsSep ", " (x: "\"${x}\"") xs} }";

  fmtIntSet =
    xs:
    if builtins.length xs == 1 then
      builtins.toString (builtins.elemAt xs 0)
    else
      "{ ${lib.concatMapStringsSep ", " builtins.toString xs} }";

  fmtIpSet =
    xs:
    if builtins.length xs == 1 then
      builtins.elemAt xs 0
    else
      "{ ${lib.concatStringsSep ", " xs} }";

  mkExpr = parts: lib.concatStringsSep " " (lib.filter (x: x != "") parts);

  ifaceExpr =
    keyword: ifaces:
    if ifaces == [ ] then
      ""
    else
      "${keyword} ${fmtQuotedSet ifaces}";

  matchVariants =
    match:
    let
      family = match.family or "any";
      proto = match.proto or "any";
      dports = match.dports or [ ];
      l4 =
        if proto == "tcp" then
          mkExpr [
            "meta l4proto tcp"
            (if dports == [ ] then "" else "tcp dport ${fmtIntSet dports}")
          ]
        else if proto == "udp" then
          mkExpr [
            "meta l4proto udp"
            (if dports == [ ] then "" else "udp dport ${fmtIntSet dports}")
          ]
        else
          "";
    in
    if proto == "icmp" && family == "any" then
      [
        { expr = "ip protocol icmp"; }
        { expr = "ip6 nexthdr ipv6-icmp"; }
      ]
    else if proto == "icmp" && family == 4 then
      [
        { expr = "ip protocol icmp"; }
      ]
    else if proto == "icmp" && family == 6 then
      [
        { expr = "ip6 nexthdr ipv6-icmp"; }
      ]
    else if family == "any" || family == null then
      [
        { expr = l4; }
      ]
    else
      [
        { expr = l4; }
      ];

  sourceIfacesFor =
    from:
    if builtins.isString from && from == "any" then
      [ ]
    else if (from.kind or null) == "tenant-set" then
      map (tenant: tenantToIf.${tenant}) from.members
    else if (from.kind or null) == "tenant" then
      [ tenantToIf.${from.name} ]
    else if (from.kind or null) == "external" then
      [ uplinkIf ]
    else
      abort "container/nftables.nix: unsupported relation.from: ${builtins.toJSON from}";

  destinationInfoFor =
    to:
    if builtins.isString to && to == "any" then
      {
        kind = "any";
        interfaces = [ ];
        ipv4 = [ ];
        ipv6 = [ ];
        label = "any";
      }
    else if (to.kind or null) == "tenant-set" then
      {
        kind = "tenant-set";
        interfaces = map (tenant: tenantToIf.${tenant}) to.members;
        ipv4 = [ ];
        ipv6 = [ ];
        label = "tenant-set:${lib.concatStringsSep "," to.members}";
      }
    else if (to.kind or null) == "tenant" then
      {
        kind = "tenant";
        interfaces = [ tenantToIf.${to.name} ];
        ipv4 = [ ];
        ipv6 = [ ];
        label = "tenant:${to.name}";
      }
    else if (to.kind or null) == "external" then
      {
        kind = "external";
        interfaces = [ uplinkIf ];
        ipv4 = [ ];
        ipv6 = [ ];
        label = "external:${to.name or "wan"}";
      }
    else if (to.kind or null) == "service" then
      let
        service =
          if builtins.hasAttr to.name serviceData then
            serviceData.${to.name}
          else
            abort "container/nftables.nix: service '${to.name}' missing from communicationContract.services";
      in
      {
        kind = "service";
        interfaces = service.interfaces;
        ipv4 = service.ipv4;
        ipv6 = service.ipv6;
        label = "service:${to.name}";
      }
    else
      abort "container/nftables.nix: unsupported relation.to: ${builtins.toJSON to}";

  sourceLabelFor =
    from:
    if builtins.isString from && from == "any" then
      "src:any"
    else if (from.kind or null) == "tenant-set" then
      "src:tenant-set:${lib.concatStringsSep "," from.members}"
    else if (from.kind or null) == "tenant" then
      "src:tenant:${from.name}"
    else if (from.kind or null) == "external" then
      "src:external:${from.name or "wan"}"
    else
      "src:unknown";

  finalizeVariant =
    variant: dstInfo:
    if dstInfo.kind != "service" then
      [ variant ]
    else if dstInfo.ipv4 == [ ] && dstInfo.ipv6 == [ ] then
      [ variant ]
    else
      (lib.optional (dstInfo.ipv4 != [ ]) {
        expr = mkExpr [ variant.expr "ip daddr ${fmtIpSet dstInfo.ipv4}" ];
      })
      ++ (lib.optional (dstInfo.ipv6 != [ ]) {
        expr = mkExpr [ variant.expr "ip6 daddr ${fmtIpSet dstInfo.ipv6}" ];
      });

  actionFor =
    action:
    if action == "allow" then
      "accept"
    else if action == "deny" then
      "drop"
    else
      abort "container/nftables.nix: unsupported relation action '${action}'";

  ruleStrings =
    lib.concatMap (
      relation:
      let
        srcIfs = sourceIfacesFor relation.from;
        dstInfo = destinationInfoFor relation.to;
        comment = "${relationName relation} policy=${policyTargetName} ${sourceLabelFor relation.from} dst:${dstInfo.label}";
      in
      lib.concatMap (
        match:
        let
          baseVariants = matchVariants match;
        in
        lib.concatMap (
          variant:
          map (
            finalVariant:
            mkExpr [
              (ifaceExpr "iifname" srcIfs)
              (ifaceExpr "oifname" dstInfo.interfaces)
              finalVariant.expr
              "counter"
              (actionFor relation.action)
              ''comment "${comment}"''
            ]
          ) (finalizeVariant variant dstInfo)
        ) baseVariants
      ) relation.match
    ) relations;

  rulesText = lib.concatMapStringsSep "\n        " (rule: "${rule};") ruleStrings;
in
{
  networking.nftables.enable = true;

  networking.nftables.ruleset = ''
    table inet edge_policy {
      chain input {
        type filter hook input priority 0; policy accept;
      }

      chain forward {
        type filter hook forward priority 0; policy drop;
        ct state invalid drop;
        ct state established,related accept;
        ${rulesText}
      }

      chain output {
        type filter hook output priority 0; policy accept;
      }
    }
  '';
}
