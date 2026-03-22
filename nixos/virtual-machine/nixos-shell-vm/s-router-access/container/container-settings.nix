{
  config,
  lib,
  outPath,
  fabricCompiled,
  ...
}:

let
  hostname = config.networking.hostName;

  inventory = import ../inventory.nix;

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

  unitBelongsToHost =
    unitName:
      unitName == hostname
      || lib.hasPrefix "${hostname}-" unitName;

  selectedUnits = lib.filter unitBelongsToHost allUnitNames;

  _selectedNonEmpty =
    if selectedUnits != [ ] then
      true
    else
      throw ''
        container-settings:

        No units matched physical host '${hostname}'.

        Expected:
          ${hostname}
          ${hostname}-*

        Available units:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ allUnitNames)}
      '';

  policyBase =
    if inventory ? policyAccessTransitBase then
      inventory.policyAccessTransitBase
    else
      100;

  vlanMap =
    if inventory ? tenantVlanMap && builtins.isAttrs inventory.tenantVlanMap then
      inventory.tenantVlanMap
    else
      throw ''
        container-settings:

        inventory.tenantVlanMap missing.

        inventory:
        ${builtins.toJSON inventory}
      '';

  suffixForUnit =
    unitName:
      if lib.hasPrefix "${hostname}-" unitName then
        lib.removePrefix "${hostname}-" unitName
      else
        unitName;

  vlanForUnit =
    unitName:
    let
      node =
        if builtins.hasAttr unitName nodes then
          nodes.${unitName}
        else
          throw ''
            container-settings:

            Missing node context for unit '${unitName}'.
          '';

      attachments =
        if node ? attachments && builtins.isList node.attachments then
          node.attachments
        else
          [ ];

      tenantAttachments =
        builtins.filter (
          a:
            builtins.isAttrs a
            && (a.kind or null) == "tenant"
            && (a ? name)
        ) attachments;

      tenantName =
        if builtins.length tenantAttachments == 1 then
          (builtins.head tenantAttachments).name
        else
          suffixForUnit unitName;
    in
    if builtins.hasAttr tenantName vlanMap then
      vlanMap.${tenantName}
    else
      throw ''
        container-settings:

        No VLAN mapping for tenant '${tenantName}'.

        Known tenants:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames vlanMap)}
      '';

  mkContainer =
    unitName:
    let
      fabricNodeContext = nodes.${unitName};

      vid = vlanForUnit unitName;
      transitVid = policyBase + vid;
    in
    {
      name = unitName;
      value = {
        autoStart = true;
        privateNetwork = true;

        extraVeths = {
          "lan-${toString vid}" = {
            hostBridge = "br-lan-${toString vid}";
          };
          "tr-${toString vid}" = {
            hostBridge = "br-tr-${toString vid}";
          };
        };

        specialArgs = {
          inherit outPath fabricNodeContext;
          vlanId = vid;
          policyAccessTransitBase = policyBase;
        };

        config = { ... }: {
          imports = [
            ./node-from-topology.nix
            ./networkd-from-topology.nix
            ./kea.nix
            ./kea-services.nix
            ./dns.nix
            ./radvd.nix
            ../debugging-packages.nix
          ];

          boot.isContainer = true;
          system.stateVersion = "25.11";

          networking.hostName = unitName;
          networking.useHostResolvConf = false;

          networking.firewall.enable = false;
          services.resolved.enable = false;
        };

        additionalCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_SYS_ADMIN"
          "CAP_NET_BIND_SERVICE"
          "CAP_NET_RAW"
        ];
      };
    };

in
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  containers = builtins.listToAttrs (map mkContainer selectedUnits);
}
