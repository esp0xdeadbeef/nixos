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
       && inventory.deployment ? host
       && builtins.isAttrs inventory.deployment.host
    then
      inventory.deployment.host
    else
      throw ''
        container-settings:

        inventory.deployment.host missing.

        inventory:
        ${builtins.toJSON inventory}
      '';

  hostConfig =
    if builtins.hasAttr hostname deploymentHosts then
      deploymentHosts.${hostname}
    else
      throw ''
        container-settings:

        inventory.deployment.host.${hostname} missing.

        Known deployment hosts:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames deploymentHosts)}
      '';

  uplink =
    if hostConfig ? uplink && builtins.isAttrs hostConfig.uplink then
      hostConfig.uplink
    else
      throw ''
        container-settings:

        inventory.deployment.host.${hostname}.uplink missing.

        host config:
        ${builtins.toJSON hostConfig}
      '';

  wanConfig =
    if uplink ? wan && builtins.isAttrs uplink.wan then
      uplink.wan
    else
      throw ''
        container-settings:

        inventory.deployment.host.${hostname}.uplink.wan missing.

        uplink config:
        ${builtins.toJSON uplink}
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

  enterprises =
    if fabricCompiled ? enterprise && builtins.isAttrs fabricCompiled.enterprise then
      fabricCompiled.enterprise
    else
      throw ''
        container-settings:

        fabricCompiled.enterprise missing.

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

  sites =
    if enterprise ? site && builtins.isAttrs enterprise.site then
      enterprise.site
    else
      throw ''
        container-settings:

        enterprise.site missing for '${enterpriseName}'.

        Enterprise keys:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames enterprise)}
      '';

  siteName =
    let names = builtins.attrNames sites;
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

  site = sites.${siteName};

  units =
    if site ? units && builtins.isAttrs site.units then
      site.units
    else
      throw ''
        container-settings:

        site.units missing for ${enterpriseName}.${siteName}

        Site keys:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames site)}
      '';

  nodes =
    if site ? nodes && builtins.isAttrs site.nodes then
      site.nodes
    else
      throw ''
        container-settings:

        site.nodes missing for ${enterpriseName}.${siteName}

        Site keys:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames site)}
      '';

  allUnitNames = builtins.attrNames units;

  unitBelongsToHost = unitName: lib.hasPrefix "${hostname}-" unitName;

  selectedUnits = lib.filter unitBelongsToHost allUnitNames;

  _selectedNonEmpty =
    if selectedUnits != [ ] then
      true
    else
      throw ''
        container-settings:

        No units matched physical host '${hostname}'.

        Expected prefix:
          ${hostname}-

        Available units:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ allUnitNames)}
      '';

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

  mkContainer =
    unitName:
    let
      fabricNodeContext =
        if builtins.hasAttr unitName nodes then
          nodes.${unitName}
        else
          throw ''
            container-settings:

            Missing node context for unit '${unitName}'.

            Available node keys:
            ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames nodes)}
          '';

      role =
        if fabricNodeContext ? role then
          fabricNodeContext.role
        else
          throw ''
            container-settings:

            Node '${unitName}' missing role.

            Node keys:
            ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames fabricNodeContext)}
          '';

      containerTemplate =
        if role == "core" then
          "wan"
        else
          throw ''
            container-settings:

            Host '${hostname}' only supports core-role units right now.

            Unit '${unitName}' has role '${role}'.
          '';

      containerPath = ./. + "/container-${containerTemplate}";
      containerName = containerTemplate;
    in
    {
      name = unitName;
      value = {
        autoStart = true;
        privateNetwork = true;

        extraVeths = {
          "${containerName}-wan" = {
            hostBridge = "br-upstream";
          };
          "${containerName}-lan" = {
            hostBridge = "br-fabric";
          };
        };

        specialArgs = {
          inherit fabricNodeContext containerName pppoeConfig;
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
