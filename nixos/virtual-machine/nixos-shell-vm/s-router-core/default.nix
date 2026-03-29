{
  inputs,
  outPath,
  config,
  pkgs,
  lib,
  ...
}:

let
  renderer = inputs.network-renderer-nixos.lib.renderer;

  system = pkgs.stdenv.hostPlatform.system;

  inventoryPath = ../inventory.nix;
  intentPath = "${outPath}/library/100-fabric-routing/inputs/intent.nix";

  inventory = renderer.loadInventory inventoryPath;
  intent = renderer.loadIntent intentPath;

  compilerOut = renderer.buildCompiler {
    inherit intent system;
  };

  forwardingOut = renderer.buildForwarding {
    inherit compilerOut system;
  };

  controlPlaneOut = renderer.buildControlPlane {
    inherit forwardingOut inventory system;
  };

  runtimeContext = import "${inputs.network-renderer-nixos}/lib/runtime-context.nix" {
    inherit lib;
  };

  cpmAdapter = import "${inputs.network-renderer-nixos}/lib/cpm-runtime-adapter.nix" {
    inherit lib;
  };

  roles = import "${inputs.network-renderer-nixos}/lib/s88-role-registry.nix" {
    inherit lib;
  };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  hostName = config.networking.hostName;

  renderHosts =
    if
      inventory ? render
      && builtins.isAttrs inventory.render
      && inventory.render ? hosts
      && builtins.isAttrs inventory.render.hosts
    then
      inventory.render.hosts
    else
      { };

  renderHostConfig =
    if builtins.hasAttr hostName renderHosts && builtins.isAttrs renderHosts.${hostName} then
      renderHosts.${hostName}
    else
      { };

  deploymentHosts =
    if
      inventory ? deployment
      && builtins.isAttrs inventory.deployment
      && inventory.deployment ? hosts
      && builtins.isAttrs inventory.deployment.hosts
    then
      inventory.deployment.hosts
    else
      { };

  deploymentHostNames = sortedAttrNames deploymentHosts;

  deploymentHostName =
    if
      renderHostConfig ? deploymentHost
      && builtins.isString renderHostConfig.deploymentHost
      && builtins.hasAttr renderHostConfig.deploymentHost deploymentHosts
    then
      renderHostConfig.deploymentHost
    else if builtins.hasAttr hostName deploymentHosts then
      hostName
    else if builtins.length deploymentHostNames == 1 then
      builtins.head deploymentHostNames
    else
      hostName;

  hostConfig =
    if builtins.hasAttr deploymentHostName deploymentHosts then
      deploymentHosts.${deploymentHostName}
    else
      throw ''
        s-router-core/default.nix: deployment host '${deploymentHostName}' missing

        known deployment hosts:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ deploymentHostNames)}
      '';

  uplinksRaw =
    if hostConfig ? uplinks && builtins.isAttrs hostConfig.uplinks then
      hostConfig.uplinks
    else
      throw "s-router-core/default.nix: hostConfig.uplinks missing";

  uplinkNames = sortedAttrNames uplinksRaw;

  bridgeNetworks =
    if hostConfig ? bridgeNetworks && builtins.isAttrs hostConfig.bridgeNetworks then
      hostConfig.bridgeNetworks
    else
      { };

  runtimeRole =
    if renderHostConfig ? runtimeRole && builtins.isString renderHostConfig.runtimeRole then
      renderHostConfig.runtimeRole
    else
      "core";

  runtimeTargets = runtimeContext.runtimeTargets controlPlaneOut;

  allUnitNames = sortedAttrNames runtimeTargets;

  realizationNodes =
    if
      inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      { };

  logicalNodeNameForUnit =
    unitName:
    let
      target = runtimeTargets.${unitName};
    in
    if
      target ? logicalNode
      && builtins.isAttrs target.logicalNode
      && target.logicalNode ? name
      && builtins.isString target.logicalNode.name
    then
      target.logicalNode.name
    else
      unitName;

  placementHostForUnit =
    unitName:
    let
      target = runtimeTargets.${unitName};
    in
    if
      target ? placement
      && builtins.isAttrs target.placement
      && target.placement ? host
      && builtins.isString target.placement.host
    then
      target.placement.host
    else
      null;

  realizationHostForUnit =
    unitName:
    if
      builtins.hasAttr unitName realizationNodes
      && builtins.isAttrs realizationNodes.${unitName}
      && realizationNodes.${unitName} ? host
      && builtins.isString realizationNodes.${unitName}.host
    then
      realizationNodes.${unitName}.host
    else
      null;

  unitBelongsToMachine =
    unitName:
    let
      logicalNodeName = logicalNodeNameForUnit unitName;
      placementHost = placementHostForUnit unitName;
      realizationHost = realizationHostForUnit unitName;
    in
    logicalNodeName == hostName
    || lib.hasPrefix "${hostName}-" logicalNodeName
    || placementHost == deploymentHostName
    || realizationHost == deploymentHostName;

  selectedUnits = lib.filter (
    unitName:
    runtimeContext.roleForUnit {
      cpm = controlPlaneOut;
      inherit unitName;
    } == runtimeRole
    && unitBelongsToMachine unitName
  ) allUnitNames;

  _selectedUnitsNonEmpty =
    if selectedUnits != [ ] then
      true
    else
      throw ''
        s-router-core/default.nix: no units matched host '${hostName}' for runtimeRole '${runtimeRole}'

        deploymentHostName:
          ${deploymentHostName}

        available runtime targets:
          ${builtins.concatStringsSep "\n  " allUnitNames}
      '';

  renderedDeploymentHost = renderer.renderHostNetwork {
    hostName = deploymentHostName;
    cpm = controlPlaneOut;
    inventory = inventory;
  };

  renderedBridgeNameMap = renderedDeploymentHost.bridgeNameMap or { };

  renderedDeploymentHostDebug = {
    hostName = renderedDeploymentHost.hostName or null;
    deploymentHostName = renderedDeploymentHost.deploymentHostName or null;
    runtimeRole = renderedDeploymentHost.runtimeRole or null;
    selectedUnits = renderedDeploymentHost.selectedUnits or [ ];
    selectedRoleNames = renderedDeploymentHost.selectedRoleNames or [ ];
    bridgeNameMap = renderedDeploymentHost.bridgeNameMap or { };
    bridges = renderedDeploymentHost.bridges or { };
    netdevs = renderedDeploymentHost.netdevs or { };
    networks = renderedDeploymentHost.networks or { };
    attachTargets = renderedDeploymentHost.attachTargets or [ ];
    localAttachTargets = renderedDeploymentHost.localAttachTargets or [ ];
    uplinks = renderedDeploymentHost.uplinks or { };
    transitBridges = renderedDeploymentHost.transitBridges or { };
    containers = builtins.listToAttrs (
      map (containerName: {
        name = containerName;
        value =
          let
            container = renderedDeploymentHost.containers.${containerName};
          in
          {
            autoStart = container.autoStart or false;
            privateNetwork = container.privateNetwork or false;
            extraVeths = container.extraVeths or { };
            bindMounts = container.bindMounts or { };
            allowedDevices = container.allowedDevices or [ ];
            additionalCapabilities = container.additionalCapabilities or [ ];
            specialArgs = {
              unitName =
                if container ? specialArgs && container.specialArgs ? unitName then
                  container.specialArgs.unitName
                else
                  containerName;
              deploymentHostName =
                if container ? specialArgs && container.specialArgs ? deploymentHostName then
                  container.specialArgs.deploymentHostName
                else
                  null;
              s88RoleName =
                if container ? specialArgs && container.specialArgs ? s88RoleName then
                  container.specialArgs.s88RoleName
                else
                  null;
            };
          };
      }) (sortedAttrNames (renderedDeploymentHost.containers or { }))
    );
    debug = renderedDeploymentHost.debug or { };
  };

  localAttachTargets = lib.filter (target: builtins.elem (target.unitName or "") selectedUnits) (
    renderedDeploymentHost.attachTargets or [ ]
  );

  maybeUniqueAttachTarget =
    description: predicate:
    let
      matches = lib.filter predicate localAttachTargets;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else if matches == [ ] then
      null
    else
      throw ''
        s-router-core/default.nix: could not uniquely resolve ${description} attach target

        selected units:
        ${builtins.toJSON selectedUnits}

        matching targets:
        ${builtins.toJSON matches}

        all local targets:
        ${builtins.toJSON localAttachTargets}
      '';

  wanAttachTarget = maybeUniqueAttachTarget "wan" (
    target: (target.connectivity.sourceKind or null) == "wan"
  );

  fabricAttachTarget = maybeUniqueAttachTarget "fabric" (
    target: (target.connectivity.sourceKind or null) == "p2p"
  );

  wanUplinkName =
    if
      renderHostConfig ? wanUplink
      && builtins.isString renderHostConfig.wanUplink
      && builtins.hasAttr renderHostConfig.wanUplink uplinksRaw
    then
      renderHostConfig.wanUplink
    else if uplinksRaw ? upstream-core && builtins.isAttrs uplinksRaw.upstream-core then
      "upstream-core"
    else if builtins.length uplinkNames == 1 then
      builtins.head uplinkNames
    else
      throw ''
        s-router-core/default.nix: WAN uplink selection missing and fallback is ambiguous

        known uplinks:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ uplinkNames)}
      '';

  fabricUplinkName =
    if
      renderHostConfig ? fabricUplink
      && builtins.isString renderHostConfig.fabricUplink
      && builtins.hasAttr renderHostConfig.fabricUplink uplinksRaw
    then
      renderHostConfig.fabricUplink
    else if uplinksRaw ? fabric && builtins.isAttrs uplinksRaw.fabric then
      "fabric"
    else if uplinksRaw ? trunk && builtins.isAttrs uplinksRaw.trunk then
      "trunk"
    else
      let
        candidates = lib.filter (name: name != wanUplinkName && name != "management") uplinkNames;
      in
      if builtins.length candidates == 1 then builtins.head candidates else null;

  uplinks = builtins.mapAttrs (
    uplinkName: uplink:
    let
      originalBridge = uplink.bridge;

      renderedBridge =
        if uplinkName == wanUplinkName && wanAttachTarget != null then
          wanAttachTarget.renderedHostBridgeName
        else if
          fabricUplinkName != null && uplinkName == fabricUplinkName && fabricAttachTarget != null
        then
          fabricAttachTarget.renderedHostBridgeName
        else if builtins.hasAttr originalBridge renderedBridgeNameMap then
          renderedBridgeNameMap.${originalBridge}
        else
          originalBridge;
    in
    uplink
    // {
      inherit originalBridge;
      bridge = renderedBridge;
    }
  ) uplinksRaw;

  bridgeNetworkFor =
    uplink:
    let
      originalBridge =
        if uplink ? originalBridge && builtins.isString uplink.originalBridge then
          uplink.originalBridge
        else
          uplink.bridge;
    in
    if builtins.hasAttr originalBridge bridgeNetworks then
      bridgeNetworks.${originalBridge}
    else
      { ConfigureWithoutCarrier = true; };

  synthesizedTransitLinks = lib.unique (
    lib.concatMap (
      nodeName:
      let
        node = realizationNodes.${nodeName};
        ports = if node ? ports && builtins.isAttrs node.ports then node.ports else { };
      in
      if (node.host or null) == deploymentHostName then
        lib.concatMap (
          portName:
          let
            port = ports.${portName};
          in
          lib.optionals
            (
              builtins.isAttrs port
              && port ? link
              && builtins.isString port.link
              && port ? attach
              && builtins.isAttrs port.attach
              && (port.attach.kind or null) == "direct"
            )
            [
              port.link
            ]
        ) (builtins.attrNames ports)
      else
        [ ]
    ) (builtins.attrNames realizationNodes)
  );

  transitBridges =
    if hostConfig ? transitBridges && builtins.isAttrs hostConfig.transitBridges then
      hostConfig.transitBridges
    else
      builtins.listToAttrs (
        map (linkName: {
          name = linkName;
          value = {
            name = linkName;
          };
        }) synthesizedTransitLinks
      );

  transitNames = sortedAttrNames transitBridges;

  parentNames = lib.unique (map (uplinkName: uplinks.${uplinkName}.parent) uplinkNames);

  transitNamesForUplink =
    uplinkName:
    lib.filter (
      transitName:
      let
        transit = transitBridges.${transitName};
      in
      (transit.parentUplink or null) == uplinkName
    ) transitNames;

  vlanIfNameFor =
    uplinkName:
    let
      uplink = uplinks.${uplinkName};
    in
    if (uplink.mode or "") == "vlan" then "${uplink.parent}.${toString uplink.vlan}" else null;

  uplinkNetdevs = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        transitNamesOnUplink = transitNamesForUplink uplinkName;
        vlanIfName = vlanIfNameFor uplinkName;
      in
      [
        {
          name = "10-${uplink.bridge}";
          value = {
            netdevConfig = {
              Name = uplink.bridge;
              Kind = "bridge";
            };
          };
        }
      ]
      ++ lib.optionals ((uplink.mode or "") == "vlan") [
        {
          name = "11-${vlanIfName}";
          value = {
            netdevConfig = {
              Name = vlanIfName;
              Kind = "vlan";
            };
            vlanConfig.Id = uplink.vlan;
          };
        }
      ]
      ++ lib.optionals ((uplink.mode or "") == "trunk") (
        map (
          transitName:
          let
            transit = transitBridges.${transitName};
            transitVlanIfName = "${uplink.bridge}.${toString transit.vlan}";
          in
          {
            name = "12-${transitVlanIfName}";
            value = {
              netdevConfig = {
                Name = transitVlanIfName;
                Kind = "vlan";
              };
              vlanConfig.Id = transit.vlan;
            };
          }
        ) transitNamesOnUplink
      )
    ) uplinkNames
  );

  uplinkParentNetworks = builtins.listToAttrs (
    let
      parentEntries = map (
        parentIf:
        let
          uplinksOnParent = lib.filter (uplinkName: uplinks.${uplinkName}.parent == parentIf) uplinkNames;

          vlanChildren = lib.filter (name: name != null) (map vlanIfNameFor uplinksOnParent);

          directBridgeUplinks = lib.filter (
            uplinkName:
            let
              mode = uplinks.${uplinkName}.mode or "";
            in
            mode != "vlan"
          ) uplinksOnParent;

          _singleDirectBridge =
            if builtins.length directBridgeUplinks <= 1 then
              true
            else
              throw ''
                s-router-core/default.nix: multiple non-vlan uplinks on parent '${parentIf}' are not supported

                uplinks:
                ${builtins.concatStringsSep "\n  - " ([ "" ] ++ directBridgeUplinks)}
              '';
        in
        {
          name = "20-${parentIf}";
          value = {
            matchConfig.Name = parentIf;
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
            networkConfig = {
              ConfigureWithoutCarrier = true;
              LinkLocalAddressing = "no";
              IPv6AcceptRA = false;
            }
            // lib.optionalAttrs (vlanChildren != [ ]) {
              VLAN = vlanChildren;
            }
            // lib.optionalAttrs (builtins.length directBridgeUplinks == 1) {
              Bridge = uplinks.${builtins.head directBridgeUplinks}.bridge;
            };
          };
        }
      ) parentNames;

      vlanBridgeEntries = lib.concatMap (
        uplinkName:
        let
          uplink = uplinks.${uplinkName};
          vlanIfName = vlanIfNameFor uplinkName;
        in
        lib.optionals ((uplink.mode or "") == "vlan") [
          {
            name = "21-${vlanIfName}";
            value = {
              matchConfig.Name = vlanIfName;
              linkConfig = {
                ActivationPolicy = "always-up";
                RequiredForOnline = "no";
              };
              networkConfig = {
                Bridge = uplink.bridge;
                ConfigureWithoutCarrier = true;
                LinkLocalAddressing = "no";
                IPv6AcceptRA = false;
              };
            };
          }
        ]
      ) uplinkNames;
    in
    parentEntries ++ vlanBridgeEntries
  );

  uplinkBridgeNetworks = builtins.listToAttrs (
    map (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        transitNamesOnUplink = transitNamesForUplink uplinkName;
        baseBridgeNetworkConfig = bridgeNetworkFor uplink;
        bridgeNetworkConfig = {
          ConfigureWithoutCarrier = true;
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        }
        // baseBridgeNetworkConfig
        // lib.optionalAttrs ((uplink.mode or "") == "trunk" && transitNamesOnUplink != [ ]) {
          VLAN = map (
            transitName:
            let
              transit = transitBridges.${transitName};
            in
            "${uplink.bridge}.${toString transit.vlan}"
          ) transitNamesOnUplink;
        };
      in
      {
        name = "30-${uplink.bridge}";
        value = {
          matchConfig.Name = uplink.bridge;
          linkConfig = {
            ActivationPolicy = "always-up";
            RequiredForOnline = "no";
          };
          networkConfig = bridgeNetworkConfig;
        };
      }
    ) uplinkNames
  );

  transitNetdevs = builtins.listToAttrs (
    map (
      transitName:
      let
        transit = transitBridges.${transitName};
      in
      {
        name = "40-${transit.name}";
        value = {
          netdevConfig = {
            Name = transit.name;
            Kind = "bridge";
          };
        };
      }
    ) transitNames
  );

  transitNetworks = builtins.listToAttrs (
    lib.concatMap (
      transitName:
      let
        transit = transitBridges.${transitName};
        parentUplink = transit.parentUplink or null;
      in
      [
        {
          name = "50-${transit.name}";
          value = {
            matchConfig.Name = transit.name;
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
            networkConfig.ConfigureWithoutCarrier = true;
          };
        }
      ]
      ++
        lib.optionals
          (
            parentUplink != null
            && builtins.hasAttr parentUplink uplinks
            && (uplinks.${parentUplink}.mode or "") == "trunk"
          )
          [
            {
              name =
                let
                  uplink = uplinks.${parentUplink};
                  transitVlanIfName = "${uplink.bridge}.${toString transit.vlan}";
                in
                "51-${transitVlanIfName}";
              value =
                let
                  uplink = uplinks.${parentUplink};
                  transitVlanIfName = "${uplink.bridge}.${toString transit.vlan}";
                in
                {
                  matchConfig.Name = transitVlanIfName;
                  linkConfig = {
                    ActivationPolicy = "always-up";
                    RequiredForOnline = "no";
                  };
                  networkConfig = {
                    Bridge = transit.name;
                    ConfigureWithoutCarrier = true;
                    LinkLocalAddressing = "no";
                    IPv6AcceptRA = false;
                  };
                };
            }
          ]
    ) transitNames
  );

  shortIfName =
    name:
    if builtins.stringLength name <= 15 then
      name
    else
      let
        suffix = builtins.substring 0 6 (builtins.hashString "sha256" name);
        prefixLen = 15 - 7;
        prefix = builtins.substring 0 prefixLen name;
      in
      "${prefix}-${suffix}";

  ensureUniqueIfNames =
    names:
    let
      shortened = map (name: {
        original = name;
        rendered = shortIfName name;
      }) names;

      grouped = builtins.foldl' (
        acc: entry:
        acc
        // {
          ${entry.rendered} = (acc.${entry.rendered} or [ ]) ++ [ entry.original ];
        }
      ) { } shortened;

      collisions = lib.filterAttrs (_: v: builtins.length v > 1) grouped;
    in
    if collisions != { } then
      throw ''
        s-router-core/default.nix: interface-name collision after shortening

        ${builtins.toJSON collisions}
      ''
    else
      builtins.listToAttrs (
        map (entry: {
          name = entry.original;
          value = entry.rendered;
        }) shortened
      );

  mkRoute =
    route:
    let
      gateway =
        if route ? via4 && route.via4 != null then
          route.via4
        else if route ? via6 && route.via6 != null then
          route.via6
        else
          null;
    in
    if gateway == null then
      null
    else
      {
        Gateway = gateway;
        GatewayOnLink = true;
      }
      // lib.optionalAttrs (route ? dst && route.dst != null) {
        Destination = route.dst;
      };

  mkDynamicWanNetworkConfig =
    iface:
    let
      connectivity = iface.connectivity or { };
      isWan = (connectivity.sourceKind or null) == "wan";
      addresses = iface.addresses or [ ];

      wanUplink =
        if isWan && builtins.hasAttr wanUplinkName uplinks then uplinks.${wanUplinkName} else { };

      ipv4Enabled =
        wanUplink ? ipv4 && builtins.isAttrs wanUplink.ipv4 && (wanUplink.ipv4.enable or false);

      ipv4Dhcp =
        ipv4Enabled
        && wanUplink ? ipv4
        && builtins.isAttrs wanUplink.ipv4
        && (wanUplink.ipv4.dhcp or false);

      ipv6Enabled =
        wanUplink ? ipv6 && builtins.isAttrs wanUplink.ipv6 && (wanUplink.ipv6.enable or false);

      ipv6Dhcp =
        ipv6Enabled
        && wanUplink ? ipv6
        && builtins.isAttrs wanUplink.ipv6
        && (wanUplink.ipv6.dhcp or false);

      ipv6AcceptRA =
        ipv6Enabled
        && wanUplink ? ipv6
        && builtins.isAttrs wanUplink.ipv6
        && (wanUplink.ipv6.acceptRA or false);

      dhcpMode =
        if ipv4Dhcp && ipv6Dhcp then
          "yes"
        else if ipv4Dhcp then
          "ipv4"
        else if ipv6Dhcp then
          "ipv6"
        else
          "no";
    in
    if isWan && addresses == [ ] then
      {
        DHCP = dhcpMode;
        IPv6AcceptRA = ipv6AcceptRA;
        LinkLocalAddressing = if ipv6AcceptRA || ipv6Dhcp then "ipv6" else "no";
      }
    else
      {
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };

  mkContainerNetworks =
    {
      interfaces,
      loopback,
      interfaceNameMap,
    }:
    let
      interfaceNames = sortedAttrNames interfaces;

      loopbackAddresses = lib.filter builtins.isString [
        (loopback.addr4 or null)
        (loopback.addr6 or null)
      ];

      loopbackUnit = lib.optionalAttrs (loopbackAddresses != [ ]) {
        "00-lo" = {
          matchConfig.Name = "lo";
          address = loopbackAddresses;
          linkConfig.RequiredForOnline = "no";
          networkConfig.ConfigureWithoutCarrier = true;
        };
      };

      interfaceUnits = builtins.listToAttrs (
        map (
          ifName:
          let
            iface = interfaces.${ifName};
            renderedName = interfaceNameMap.${ifName};
            routes = lib.filter (route: route != null) (map mkRoute (iface.routes or [ ]));
            dynamicWanNetworkConfig = mkDynamicWanNetworkConfig iface;
          in
          {
            name = "10-${renderedName}";
            value = {
              matchConfig.Name = renderedName;
              networkConfig = {
                ConfigureWithoutCarrier = true;
              }
              // dynamicWanNetworkConfig;
              address = iface.addresses or [ ];
              routes = routes;
            };
          }
        ) interfaceNames
      );
    in
    loopbackUnit // interfaceUnits;

  attachTargetForInterface =
    {
      unitName,
      ifName,
      iface,
    }:
    let
      matches = lib.filter (
        target:
        (target.unitName or null) == unitName
        && (
          (target.ifName or null) == ifName
          || ((target.interface.renderedIfName or null) == (iface.renderedIfName or null))
          || ((target.hostBridgeName or null) == (iface.hostBridge or null))
        )
      ) (renderedDeploymentHost.attachTargets or [ ]);
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else if builtins.hasAttr iface.hostBridge renderedBridgeNameMap then
      {
        renderedHostBridgeName = renderedBridgeNameMap.${iface.hostBridge};
      }
    else
      throw ''
        s-router-core/default.nix: could not resolve rendered host bridge for unit '${unitName}', interface '${ifName}'

        iface.hostBridge:
        ${iface.hostBridge}

        available bridgeNameMap keys:
        ${builtins.toJSON (builtins.attrNames renderedBridgeNameMap)}

        attachTargets:
        ${builtins.toJSON (renderedDeploymentHost.attachTargets or [ ])}
      '';

  mkContainer =
    unitName:
    let
      rt = cpmAdapter.normalizedRuntimeTargetForUnit {
        cpm = controlPlaneOut;
        inherit unitName;
      };

      interfaces = rt.interfaces or { };
      interfaceNames = sortedAttrNames interfaces;

      interfaceNameMap = ensureUniqueIfNames interfaceNames;

      roleName = runtimeContext.roleForUnit {
        cpm = controlPlaneOut;
        inherit unitName;
      };

      roleConfig = if builtins.hasAttr roleName roles then roles.${roleName} else { };

      profilePath =
        if
          roleConfig ? container
          && builtins.isAttrs roleConfig.container
          && roleConfig.container ? profilePath
        then
          roleConfig.container.profilePath
        else
          null;

      additionalCapabilities =
        if
          roleConfig ? container
          && builtins.isAttrs roleConfig.container
          && roleConfig.container ? additionalCapabilities
          && builtins.isList roleConfig.container.additionalCapabilities
        then
          roleConfig.container.additionalCapabilities
        else
          [ ];

      interfaceSourceKindFor =
        ifName:
        let
          iface = interfaces.${ifName};
        in
        if
          iface ? connectivity && builtins.isAttrs iface.connectivity && iface.connectivity ? sourceKind
        then
          iface.connectivity.sourceKind
        else
          null;

      wanInterfaceNames = map (ifName: interfaceNameMap.${ifName}) (
        lib.filter (ifName: interfaceSourceKindFor ifName == "wan") interfaceNames
      );

      lanInterfaceNames = map (ifName: interfaceNameMap.${ifName}) (
        lib.filter (ifName: interfaceSourceKindFor ifName != "wan") interfaceNames
      );

      nftQuotedIfNames = names: builtins.concatStringsSep ", " (map (name: ''"${name}"'') names);

      nftIfSet = names: "{ ${nftQuotedIfNames names} }";

      coreNftRuleset =
        if roleName == "core" && wanInterfaceNames != [ ] && lanInterfaceNames != [ ] then
          ''
            table inet filter {
              chain forward {
                type filter hook forward priority 0; policy drop;
                ct state { established, related } accept
                iifname ${nftIfSet lanInterfaceNames} oifname ${nftIfSet wanInterfaceNames} accept
              }
            }

            table ip nat {
              chain postrouting {
                type nat hook postrouting priority 100; policy accept;
                oifname ${nftIfSet wanInterfaceNames} masquerade
              }
            }
          ''
        else
          null;

      extraVeths = builtins.listToAttrs (
        map (
          ifName:
          let
            iface = interfaces.${ifName};
            attachTarget = attachTargetForInterface {
              inherit unitName ifName iface;
            };
          in
          {
            name = interfaceNameMap.${ifName};
            value = {
              hostBridge = attachTarget.renderedHostBridgeName;
            };
          }
        ) interfaceNames
      );

      containerNetworks = mkContainerNetworks {
        inherit interfaces interfaceNameMap;
        loopback = rt.loopback or { };
      };
    in
    {
      name = unitName;
      value = {
        autoStart = true;
        privateNetwork = true;

        inherit extraVeths;

        additionalCapabilities = lib.unique (
          [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
          ]
          ++ additionalCapabilities
        );

        config =
          { ... }:
          {
            imports = [
              ./mount-utils.nix
            ]
            ++ lib.optionals (profilePath != null) [
              profilePath
            ];

            networking.hostName = unitName;
            networking.useNetworkd = true;
            systemd.network.enable = true;
            networking.useDHCP = false;
            networking.useHostResolvConf = lib.mkForce false;
            services.resolved.enable = lib.mkForce false;
            networking.nftables = lib.mkIf (coreNftRuleset != null) {
              enable = true;
              ruleset = coreNftRuleset;
            };
            system.stateVersion = lib.mkDefault "25.11";

            systemd.network.networks = containerNetworks;
          };
      };
    };

  debugPayload = {
    inherit
      system
      hostName
      deploymentHostName
      runtimeRole
      selectedUnits
      intentPath
      inventoryPath
      ;

    compiler = compilerOut;
    forwarding = forwardingOut;
    controlPlane = controlPlaneOut;

    rendered = {
      deploymentHost = renderedDeploymentHostDebug;
      bridgeNameMap = renderedBridgeNameMap;
      localAttachTargets = localAttachTargets;
    };

    synthesizedHostNetwork = {
      netdevs = uplinkNetdevs // transitNetdevs;
      networks = uplinkParentNetworks // uplinkBridgeNetworks // transitNetworks;
      uplinks = uplinks;
      transitBridges = transitBridges;
    };

    normalizedRuntimeTargets = builtins.listToAttrs (
      map (unitName: {
        name = unitName;
        value = cpmAdapter.normalizedRuntimeTargetForUnit {
          cpm = controlPlaneOut;
          inherit unitName;
        };
      }) selectedUnits
    );
  };

in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./mount-utils.nix
    ./sops.nix
  ];

  system.stateVersion = lib.mkForce "24.11";

  _module.args = {
    globalInventory = inventory;
    inherit
      intent
      controlPlaneOut
      compilerOut
      forwardingOut
      ;
  };

  environment.systemPackages = with pkgs; [
    nixos-container
  ];

  environment.etc."network-renderer/network-renderer-nixos.json".text = builtins.toJSON debugPayload;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = lib.mkForce false;

  systemd.network.netdevs = builtins.seq _selectedUnitsNonEmpty (uplinkNetdevs // transitNetdevs);
  systemd.network.networks = builtins.seq _selectedUnitsNonEmpty (
    uplinkParentNetworks // uplinkBridgeNetworks // transitNetworks
  );

  containers = builtins.seq _selectedUnitsNonEmpty (
    builtins.listToAttrs (map mkContainer selectedUnits)
  );
}
