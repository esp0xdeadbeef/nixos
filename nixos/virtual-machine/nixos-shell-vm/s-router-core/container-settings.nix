{
  config,
  pkgs,
  lib,
  fabricCompiled,
  ...
}:

let
  hostname = config.networking.hostName;

  inventoryImported = import ./inventory.nix;
  inventory =
    if builtins.isFunction inventoryImported then
      inventoryImported { inherit lib; }
    else
      inventoryImported;

  deploymentHosts =
    if inventory ? deployment
       && builtins.isAttrs inventory.deployment
       && inventory.deployment ? hosts
       && builtins.isAttrs inventory.deployment.hosts
    then
      inventory.deployment.hosts
    else
      throw ''
        container-settings:

        inventory.deployment.hosts missing.

        inventory:
        ${builtins.toJSON inventory}
      '';

  deploymentHostNames = lib.sort builtins.lessThan (builtins.attrNames deploymentHosts);

  deploymentHostName =
    if builtins.hasAttr hostname deploymentHosts then
      hostname
    else if builtins.length deploymentHostNames == 1 then
      builtins.head deploymentHostNames
    else
      throw ''
        container-settings:

        inventory.deployment.hosts.${hostname} missing, and hostname fallback is ambiguous.

        Current hostname:
        ${hostname}

        Known deployment hosts:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ deploymentHostNames)}
      '';

  hostConfig = deploymentHosts.${deploymentHostName};

  uplinks =
    if hostConfig ? uplinks && builtins.isAttrs hostConfig.uplinks then
      hostConfig.uplinks
    else
      throw ''
        container-settings:

        inventory.deployment.hosts.${deploymentHostName}.uplinks missing.

        host config:
        ${builtins.toJSON hostConfig}
      '';

  uplinkNames = lib.sort builtins.lessThan (builtins.attrNames uplinks);

  wanConfig =
    if uplinks ? upstream-core && builtins.isAttrs uplinks.upstream-core then
      uplinks.upstream-core
    else if builtins.length uplinkNames == 1 then
      uplinks.${builtins.head uplinkNames}
    else
      throw ''
        container-settings:

        inventory.deployment.hosts.${deploymentHostName}.uplinks.upstream-core missing and fallback is ambiguous.

        Known uplinks:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ uplinkNames)}
      '';

  _wanBridgePresent =
    if wanConfig ? bridge && builtins.isString wanConfig.bridge then
      true
    else
      throw ''
        container-settings:

        Selected WAN uplink has no bridge.

        wan config:
        ${builtins.toJSON wanConfig}
      '';

  pppoeConfig =
    if wanConfig ? pppoe && builtins.isAttrs wanConfig.pppoe then
      wanConfig.pppoe
    else
      { enable = false; };

  pppoeEnabled =
    if pppoeConfig ? enable then
      pppoeConfig.enable
    else
      false;

  realizationNodes =
    if inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      throw ''
        container-settings:

        inventory.realization.nodes missing.

        inventory:
        ${builtins.toJSON inventory}
      '';

  cpmModel =
    if fabricCompiled ? control_plane_model && builtins.isAttrs fabricCompiled.control_plane_model then
      fabricCompiled.control_plane_model
    else
      { };

  cpmData =
    if cpmModel ? data && builtins.isAttrs cpmModel.data then
      cpmModel.data
    else
      { };

  enterprises =
    if cpmData != { } then
      cpmData
    else
      throw ''
        container-settings:

        fabricCompiled.control_plane_model.data missing.

        Top-level keys:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames fabricCompiled)}
      '';

  enterpriseName =
    let names = builtins.attrNames enterprises;
    in
    if builtins.length names == 1 then
      builtins.head names
    else
      throw ''
        container-settings:

        Expected exactly 1 enterprise.

        Found:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ names)}
      '';

  enterprise = enterprises.${enterpriseName};

  siteName =
    let names = builtins.attrNames enterprise;
    in
    if builtins.length names == 1 then
      builtins.head names
    else
      throw ''
        container-settings:

        Expected exactly 1 site for enterprise '${enterpriseName}'.

        Found:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ names)}
      '';

  site = enterprise.${siteName};

  runtimeTargets =
    if site ? runtimeTargets && builtins.isAttrs site.runtimeTargets then
      site.runtimeTargets
    else
      { };

  runtimeTargetNames = builtins.attrNames runtimeTargets;

  pppoeBindMounts =
    if pppoeEnabled then
      {
        "/dev/ppp" = {
          hostPath = "/dev/ppp";
          isReadOnly = false;
        };

        "/run/secrets/pppoe-username" = {
          hostPath = config.sops.secrets.pppoe-username.path;
          isReadOnly = true;
        };

        "/run/secrets/pppoe-password" = {
          hostPath = config.sops.secrets.pppoe-password.path;
          isReadOnly = true;
        };
      }
    else
      { };

  attrValues = attrs: map (name: attrs.${name}) (builtins.attrNames attrs);

  realizationNodeForUnit =
    unitName:
      if builtins.hasAttr unitName realizationNodes then
        realizationNodes.${unitName}
      else
        throw ''
          container-settings:

          Missing realization node for unit '${unitName}'.

          Known realization nodes:
          ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames realizationNodes)}
        '';

  logicalNodeNameForUnit =
    unitName:
      let
        node = realizationNodeForUnit unitName;
      in
      if node ? logicalNode
        && builtins.isAttrs node.logicalNode
        && node.logicalNode ? name
        && builtins.isString node.logicalNode.name
      then
        node.logicalNode.name
      else
        "";

  unitBelongsToDeploymentHost =
    unitName:
      builtins.hasAttr unitName realizationNodes
      && builtins.isAttrs realizationNodes.${unitName}
      && (realizationNodes.${unitName}.host or null) == deploymentHostName;

  unitMatchesMachine =
    unitName:
      let
        logicalNodeName = logicalNodeNameForUnit unitName;
      in
      logicalNodeName == hostname
      || lib.hasPrefix "${hostname}-" logicalNodeName
      || unitBelongsToDeploymentHost unitName;

  nodeContextForUnit =
    unitName:
      if builtins.hasAttr unitName runtimeTargets then
        runtimeTargets.${unitName}
      else
        throw ''
          container-settings:

          Missing runtime target for unit '${unitName}'.

          Available runtime targets:
          ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames runtimeTargets)}
        '';

  unitRole =
    unitName:
      let
        ctx = nodeContextForUnit unitName;
      in
      if ctx ? role then
        ctx.role
      else
        throw ''
          container-settings:

          Node '${unitName}' missing role.

          Node keys:
          ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames ctx)}
        '';

  selectedUnits =
    lib.filter (
      unitName:
        unitRole unitName == "core"
        && unitMatchesMachine unitName
    ) runtimeTargetNames;

  _selectedNonEmpty =
    if selectedUnits != [ ] then
      true
    else
      throw ''
        container-settings:

        No core-role runtime targets matched this machine.

        Current hostname:
        ${hostname}

        Deployment host fallback:
        ${deploymentHostName}

        Available runtime targets:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ runtimeTargetNames)}
      '';

  runtimeTransitBridgeForUnit =
    unitName:
      let
        realizationNode = realizationNodeForUnit unitName;
        ports =
          if realizationNode ? ports && builtins.isAttrs realizationNode.ports then
            realizationNode.ports
          else
            throw ''
              container-settings:

              realization.nodes.${unitName}.ports missing or not an attrset.

              realization node:
              ${builtins.toJSON realizationNode}
            '';

        bridgePorts =
          builtins.filter (
            port:
              builtins.isAttrs port
              && port ? attach
              && builtins.isAttrs port.attach
              && (port.attach.kind or null) == "bridge"
              && (port.attach ? bridge)
              && builtins.isString port.attach.bridge
          ) (attrValues ports);

        directPorts =
          builtins.filter (
            port:
              builtins.isAttrs port
              && port ? attach
              && builtins.isAttrs port.attach
              && (port.attach.kind or null) == "direct"
              && port ? link
              && builtins.isString port.link
          ) (attrValues ports);
      in
      if builtins.length bridgePorts == 1 then
        (builtins.head bridgePorts).attach.bridge
      else if builtins.length bridgePorts == 0 && builtins.length directPorts == 1 then
        (builtins.head directPorts).link
      else
        throw ''
          container-settings:

          Expected exactly 1 bridge-backed runtime port or exactly 1 direct-link port for unit '${unitName}'.

          bridge-backed ports:
          ${builtins.toJSON bridgePorts}

          direct-link ports:
          ${builtins.toJSON directPorts}
        '';

  mkContainer =
    unitName:
    let
      fabricNodeContext = nodeContextForUnit unitName;
      containerTemplate = "wan";
      containerName = containerTemplate;
      containerPath = ./. + "/container-${containerTemplate}";
      transitBridge = runtimeTransitBridgeForUnit unitName;
    in
    {
      name = unitName;
      value = {
        autoStart = true;
        privateNetwork = true;

        extraVeths = {
          "${containerName}-wan" = {
            hostBridge = wanConfig.bridge;
          };
          "${containerName}-fabric" = {
            hostBridge = transitBridge;
          };
        };

        specialArgs = {
          inherit fabricNodeContext containerName wanConfig transitBridge;
          realizationNode = realizationNodeForUnit unitName;
        };

        bindMounts = pppoeBindMounts;

        allowedDevices =
          lib.optionals pppoeEnabled [
            {
              node = "/dev/ppp";
              modifier = "rw";
            }
          ];

        additionalCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];

        config = containerPath;
      };
    };

  containersGenerated = builtins.listToAttrs (map mkContainer selectedUnits);

in
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  containers = containersGenerated;
}
