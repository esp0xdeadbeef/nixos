{
  config,
  pkgs,
  lib,
  fabricCompiled,
  ...
}:

let
  hostname = config.networking.hostName;

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
    let
      names = builtins.attrNames enterprises;
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
    let
      names = builtins.attrNames sites;
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

  unitBelongsToHost =
    unitName: lib.hasPrefix "${hostname}-" unitName;

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
        if role == "upstream-selector" then
          "upstream-selector"
        else
          throw ''
            container-settings:

            Host '${hostname}' only supports upstream-selector-role units right now.

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
          "upstream-core" = {
            hostBridge = "br-upstream";
          };
          "upstream-policy" = {
            hostBridge = "br-fabric";
          };
        };

        specialArgs = {
          inherit fabricNodeContext containerName;
        };

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
