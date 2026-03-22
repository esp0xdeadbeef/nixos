{
  config,
  lib,
  outPath,
  fabricCompiled,
  ...
}:

let
  hostname = config.networking.hostName;

  inventoryImported = import ../inventory.nix;
  inventory =
    if builtins.isFunction inventoryImported then
      inventoryImported { inherit lib; }
    else
      inventoryImported;

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

  inventoryFabric =
    if inventory ? fabric && builtins.isAttrs inventory.fabric then
      inventory.fabric
    else
      throw ''
        container-settings:

        inventory.fabric missing.

        inventory:
        ${builtins.toJSON inventory}
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

  attrValues =
    attrs: map (name: attrs.${name}) (builtins.attrNames attrs);

  splitCIDR =
    cidr:
      let
        parts = lib.splitString "/" cidr;
      in
      if builtins.length parts == 2 then
        {
          address = builtins.elemAt parts 0;
          prefix = builtins.elemAt parts 1;
        }
      else
        throw ''
          container-settings:

          Invalid CIDR '${cidr}'.
        '';

  parseTenantVlanFromIPv4CIDR =
    cidr:
      let
        ip = (splitCIDR cidr).address;
        octets = lib.splitString "." ip;
      in
      if builtins.length octets == 4 then
        builtins.fromJSON (builtins.elemAt octets 2)
      else
        throw ''
          container-settings:

          Cannot derive tenant VLAN from IPv4 CIDR '${cidr}'.
        '';

  fabricPortsForUnit =
    unitName:
      if builtins.hasAttr unitName inventoryFabric then
        let
          node = inventoryFabric.${unitName};
        in
        if node ? ports && builtins.isAttrs node.ports then
          node.ports
        else
          throw ''
            container-settings:

            inventory.fabric.${unitName}.ports missing or not an attrset.

            inventory.fabric.${unitName}:
            ${builtins.toJSON node}
          ''
      else
        throw ''
          container-settings:

          Missing inventory.fabric entry for unit '${unitName}'.

          Known inventory.fabric units:
          ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames inventoryFabric)}

          CPM site units:
          ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames units)}
        '';

  nodeContextForUnit =
    unitName:
      if builtins.hasAttr unitName nodes then
        nodes.${unitName}
      else
        throw ''
          container-settings:

          Missing node context for unit '${unitName}'.
        '';

  tenantPortForUnit =
    unitName:
      let
        ports = fabricPortsForUnit unitName;
        tenantPorts =
          builtins.filter (
            port:
              builtins.isAttrs port
              && port ? attachment
              && builtins.isAttrs port.attachment
              && (port.attachment.kind or null) == "tenant"
              && (port.attachment ? name)
          ) (attrValues ports);
      in
      if tenantPorts != [ ] then
        builtins.head tenantPorts
      else
        throw ''
          container-settings:

          No tenant-facing inventory port found for unit '${unitName}'.

          inventory.fabric.${unitName}.ports:
          ${builtins.toJSON ports}
        '';

  tenantNameForUnit =
    unitName:
      (tenantPortForUnit unitName).attachment.name;

  tenantNetworkForUnit =
    unitName:
      let
        node = nodeContextForUnit unitName;
        tenantName = tenantNameForUnit unitName;
        networks =
          if node ? networks && builtins.isAttrs node.networks then
            node.networks
          else
            { };
      in
      if builtins.hasAttr tenantName networks then
        networks.${tenantName}
      else
        throw ''
          container-settings:

          CPM node '${unitName}' has no tenant network '${tenantName}'.

          Known node networks:
          ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames networks)}
        '';

  vlanForUnit =
    unitName:
      parseTenantVlanFromIPv4CIDR (tenantNetworkForUnit unitName).ipv4;

  transitPortForUnit =
    unitName:
      let
        ports = fabricPortsForUnit unitName;
        transitPorts =
          builtins.filter (
            port:
              builtins.isAttrs port
              && (port ? link)
              && (port ? vlan)
          ) (attrValues ports);
      in
      if transitPorts != [ ] then
        builtins.head transitPorts
      else
        throw ''
          container-settings:

          No transit inventory port found for unit '${unitName}'.

          inventory.fabric.${unitName}.ports:
          ${builtins.toJSON ports}
        '';

  transitVlanForUnit =
    unitName:
      (transitPortForUnit unitName).vlan;

  mkContainer =
    unitName:
    let
      fabricNodeContext = nodeContextForUnit unitName;
      vid = vlanForUnit unitName;
      transitVid = transitVlanForUnit unitName;
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
          "tr-${toString transitVid}" = {
            hostBridge = "br-tr-${toString transitVid}";
          };
        };

        specialArgs = {
          inherit outPath fabricNodeContext;
          vlanId = vid;
          transitVlanId = transitVid;
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
