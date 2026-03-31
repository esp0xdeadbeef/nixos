{
  inputs,
  outPath,
  lib,
  ...
}:

let
  api = inputs.network-renderer-nixos.lib;

  moduleHostName = builtins.baseNameOf (builtins.toString ./.);

  containerSelection = {
    "s-router-upstream-selector" = true;
  };

  hostBuild = api.hostBuild {
    inherit
      lib
      outPath
      ;
    hostName = moduleHostName;
    inventoryPath = ../inventory.nix;
    selectorFile = "s-router-upstream-selector/default.nix";
    containerSelection = containerSelection;
  };

  moduleArgs = hostBuild.moduleArgs or { };

  inventory =
    if moduleArgs ? globalInventory && builtins.isAttrs moduleArgs.globalInventory then
      moduleArgs.globalInventory
    else
      { };

  controlPlaneOut =
    if moduleArgs ? controlPlaneOut && builtins.isAttrs moduleArgs.controlPlaneOut then
      moduleArgs.controlPlaneOut
    else
      { };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  realizationNodes =
    if inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      { };

  cpmData =
    if controlPlaneOut ? control_plane_model
      && builtins.isAttrs controlPlaneOut.control_plane_model
      && controlPlaneOut.control_plane_model ? data
      && builtins.isAttrs controlPlaneOut.control_plane_model.data
    then
      controlPlaneOut.control_plane_model.data
    else
      { };

  siteTreeForEnterprise =
    enterprise:
    if enterprise ? site && builtins.isAttrs enterprise.site then
      enterprise.site
    else if builtins.isAttrs enterprise then
      enterprise
    else
      { };

  siteEntries =
    lib.concatMap (
      enterpriseName:
      let
        siteTree = siteTreeForEnterprise cpmData.${enterpriseName};
      in
      map
        (
          siteName:
          {
            inherit enterpriseName siteName;
            site = siteTree.${siteName};
          }
        )
        (sortedAttrNames siteTree)
    ) (sortedAttrNames cpmData);

  runtimeTargets =
    lib.foldl' (
      acc: entry:
      acc
      // (
        if entry.site ? runtimeTargets && builtins.isAttrs entry.site.runtimeTargets then
          entry.site.runtimeTargets
        else
          { }
      )
    ) { } siteEntries;

  bridgeForLink =
    unitName: linkName:
    let
      node =
        if builtins.hasAttr unitName realizationNodes
          && builtins.isAttrs realizationNodes.${unitName}
        then
          realizationNodes.${unitName}
        else
          throw ''
            s-router-upstream-selector/default.nix: realization node missing for '${unitName}'

            known realization nodes:
            ${builtins.toJSON (builtins.attrNames realizationNodes)}
          '';

      ports =
        if node ? ports && builtins.isAttrs node.ports then
          node.ports
        else
          throw "s-router-upstream-selector/default.nix: realization node '${unitName}' missing ports";

      matchingPortNames =
        lib.filter
          (
            portName:
            let
              port = ports.${portName};
            in
            builtins.isAttrs port
            && (port.link or null) == linkName
          )
          (sortedAttrNames ports);

      selectedPortName =
        if builtins.length matchingPortNames == 1 then
          builtins.head matchingPortNames
        else if matchingPortNames == [ ] then
          throw ''
            s-router-upstream-selector/default.nix: no realization port matched link '${linkName}' for '${unitName}'

            available links:
            ${builtins.toJSON (map (p: ports.${p}.link or null) (sortedAttrNames ports))}
          ''
        else
          throw ''
            s-router-upstream-selector/default.nix: multiple realization ports matched link '${linkName}' for '${unitName}'

            matches:
            ${builtins.toJSON matchingPortNames}
          '';

      port = ports.${selectedPortName};
      attach = port.attach or { };
    in
    if (attach.kind or null) == "bridge"
      && attach ? bridge
      && builtins.isString attach.bridge
    then
      attach.bridge
    else
      throw ''
        s-router-upstream-selector/default.nix: realization port '${selectedPortName}' for '${unitName}' is not bridge-backed

        port:
        ${builtins.toJSON port}
      '';

  renderedIfNameForInterface =
    iface:
    if iface ? renderedIfName && builtins.isString iface.renderedIfName then
      iface.renderedIfName
    else if iface ? runtimeIfName && builtins.isString iface.runtimeIfName then
      iface.runtimeIfName
    else
      null;

  extraVethOverridesForUnit =
    unitName:
    let
      target =
        if builtins.hasAttr unitName runtimeTargets
          && builtins.isAttrs runtimeTargets.${unitName}
        then
          runtimeTargets.${unitName}
        else
          throw ''
            s-router-upstream-selector/default.nix: runtime target missing for '${unitName}'

            known runtime targets:
            ${builtins.toJSON (builtins.attrNames runtimeTargets)}
          '';

      interfaces =
        if target ? effectiveRuntimeRealization
          && builtins.isAttrs target.effectiveRuntimeRealization
          && target.effectiveRuntimeRealization ? interfaces
          && builtins.isAttrs target.effectiveRuntimeRealization.interfaces
        then
          target.effectiveRuntimeRealization.interfaces
        else
          throw "s-router-upstream-selector/default.nix: runtime interfaces missing for '${unitName}'";
    in
    builtins.listToAttrs (
      lib.filter
        (entry: entry != null)
        (
          map
            (
              ifaceName:
              let
                iface = interfaces.${ifaceName};
                backingRef = iface.backingRef or { };

                renderedIfName = renderedIfNameForInterface iface;

                linkName =
                  if (backingRef.kind or null) == "link"
                    && backingRef ? name
                    && builtins.isString backingRef.name
                  then
                    backingRef.name
                  else
                    null;
              in
              if renderedIfName != null && linkName != null then
                {
                  name = renderedIfName;
                  value = {
                    hostBridge = bridgeForLink unitName linkName;
                  };
                }
              else
                null
            )
            (sortedAttrNames interfaces)
        )
    );

  extraContainerOptions = {
    "*" = {
      autoStart = true;
    };

    "s-router-upstream-selector" = {
      additionalCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };
  };

  extraContainerModules = {
    "*" = [ ];

    "s-router-upstream-selector" = [
      ./container-upstream-selector/nftables.nix
      ({ pkgs, ... }: {
        environment.systemPackages = with pkgs; [
          tcpdump
          iproute2
          traceroute
          dnsutils
          tmux
          nftables
          jq
          gron
        ];
      })
    ];
  };

  mergeContainer =
    name: rendered:
    let
      global = extraContainerOptions."*" or { };
      named = extraContainerOptions.${name} or { };

      renderedMerged =
        lib.recursiveUpdate (lib.recursiveUpdate rendered global) named;

      baseConfig =
        renderedMerged.config or ({ ... }: { });

      modules =
        (extraContainerModules."*" or [ ])
        ++ (extraContainerModules.${name} or [ ]);

      vethOverrides =
        if builtins.hasAttr name runtimeTargets then
          extraVethOverridesForUnit name
        else
          { };
    in
    renderedMerged
    // {
      extraVeths =
        lib.recursiveUpdate (renderedMerged.extraVeths or { }) vethOverrides;

      config = { ... }: {
        imports = [ baseConfig ] ++ modules;
      };
    };

  containers =
    lib.mapAttrs mergeContainer (hostBuild.renderedHostNetwork.containers or { });

  _validatedContainers =
    if builtins.attrNames containers != [ ] then
      true
    else
      throw ''
        s-router-upstream-selector/default.nix: no containers were rendered for host '${moduleHostName}'

        containerSelection:
        ${builtins.toJSON containerSelection}

        rendered container names:
        ${builtins.toJSON (builtins.attrNames (hostBuild.renderedHostNetwork.containers or { }))}

        selected units:
        ${builtins.toJSON (hostBuild.renderedHostNetwork.selectedUnits or [ ])}

        selected roles:
        ${builtins.toJSON (hostBuild.renderedHostNetwork.selectedRoleNames or [ ])}
      '';
in
builtins.seq _validatedContainers {
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./mount-utils.nix
    ./sops.nix
  ];

  system.stateVersion = lib.mkForce "24.11";

  _module.args = moduleArgs;

  environment.etc."network-renderer/network-renderer-nixos.json".text =
    builtins.toJSON (hostBuild.debugPayload or { });

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.networkmanager.enable = false;
  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = lib.mkForce false;

  systemd.network.netdevs = hostBuild.renderedHostNetwork.netdevs or { };
  systemd.network.networks = hostBuild.renderedHostNetwork.networks or { };
  containers = containers;
}
