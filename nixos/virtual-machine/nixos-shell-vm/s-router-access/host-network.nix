{
  config,
  lib,
  fabricCompiled,
  ...
}:

let
  inventoryImported = import ./inventory.nix;
  inventory =
    if builtins.isFunction inventoryImported then
      inventoryImported { inherit lib; }
    else
      inventoryImported;

  hostname = config.networking.hostName;

  deploymentHosts =
    if inventory ? deployment
       && builtins.isAttrs inventory.deployment
       && inventory.deployment ? host
       && builtins.isAttrs inventory.deployment.host
    then
      inventory.deployment.host
    else
      throw ''
        host-network:

        inventory.deployment.host missing.

        inventory:
        ${builtins.toJSON inventory}
      '';

  hostConfig =
    if builtins.hasAttr hostname deploymentHosts then
      deploymentHosts.${hostname}
    else
      throw ''
        host-network:

        inventory.deployment.host.${hostname} missing.

        Known deployment hosts:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames deploymentHosts)}
      '';

  uplink =
    if hostConfig ? uplink && builtins.isAttrs hostConfig.uplink then
      hostConfig.uplink
    else
      throw ''
        host-network:

        inventory.deployment.host.${hostname}.uplink missing.

        host config:
        ${builtins.toJSON hostConfig}
      '';

  mgmt =
    if uplink ? management && builtins.isAttrs uplink.management then
      uplink.management
    else
      throw ''
        host-network:

        inventory.deployment.host.${hostname}.uplink.management missing.

        uplink config:
        ${builtins.toJSON uplink}
      '';

  trunkParent =
    if uplink ? parent && builtins.isString uplink.parent then
      uplink.parent
    else
      throw ''
        host-network:

        uplink.parent missing or not a string.

        uplink config:
        ${builtins.toJSON uplink}
      '';

  mgmtVlan =
    if mgmt ? vlan then
      mgmt.vlan
    else
      throw ''
        host-network:

        uplink.management.vlan missing.

        management config:
        ${builtins.toJSON mgmt}
      '';

  mgmtBridge =
    if mgmt ? bridge && builtins.isString mgmt.bridge then
      mgmt.bridge
    else
      throw ''
        host-network:

        uplink.management.bridge missing or not a string.

        management config:
        ${builtins.toJSON mgmt}
      '';

  mgmtAddressing =
    if mgmt ? addressing && builtins.isAttrs mgmt.addressing then
      mgmt.addressing
    else
      {
        ipv4 = { mode = "dhcp"; };
        ipv6 = { mode = "disabled"; };
      };

  mgmtIPv4 =
    if mgmtAddressing ? ipv4 && builtins.isAttrs mgmtAddressing.ipv4 then
      mgmtAddressing.ipv4
    else
      { mode = "dhcp"; };

  mgmtIPv6 =
    if mgmtAddressing ? ipv6 && builtins.isAttrs mgmtAddressing.ipv6 then
      mgmtAddressing.ipv6
    else
      { mode = "disabled"; };

  mgmtIPv4Mode =
    if mgmtIPv4 ? mode && builtins.isString mgmtIPv4.mode then
      mgmtIPv4.mode
    else
      "dhcp";

  mgmtIPv6Mode =
    if mgmtIPv6 ? mode && builtins.isString mgmtIPv6.mode then
      mgmtIPv6.mode
    else
      "disabled";

  _validateIPv4Mode =
    if builtins.elem mgmtIPv4Mode [ "dhcp" "static" "disabled" ] then
      true
    else
      throw ''
        host-network:

        Unsupported management.addressing.ipv4.mode '${mgmtIPv4Mode}'.
        Supported: dhcp, static, disabled
      '';

  _validateIPv6Mode =
    if builtins.elem mgmtIPv6Mode [ "dhcp" "static" "ra-only" "disabled" ] then
      true
    else
      throw ''
        host-network:

        Unsupported management.addressing.ipv6.mode '${mgmtIPv6Mode}'.
        Supported: dhcp, static, ra-only, disabled
      '';

  mgmtVlanIf = "${trunkParent}.${toString mgmtVlan}";

  inventoryFabric =
    if inventory ? fabric && builtins.isAttrs inventory.fabric then
      inventory.fabric
    else
      { };

  enterprises =
    if fabricCompiled ? enterprise && builtins.isAttrs fabricCompiled.enterprise then
      fabricCompiled.enterprise
    else
      throw ''
        host-network:

        fabricCompiled.enterprise missing.
      '';

  enterpriseName =
    let
      names = builtins.attrNames enterprises;
    in
    if builtins.length names == 1 then
      builtins.head names
    else
      throw ''
        host-network:

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
        host-network:

        enterprise.site missing for '${enterpriseName}'.
      '';

  siteName =
    let
      names = builtins.attrNames sites;
    in
    if builtins.length names == 1 then
      builtins.head names
    else
      throw ''
        host-network:

        Expected exactly 1 site for enterprise '${enterpriseName}'.

        Found:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ names)}
      '';

  site = sites.${siteName};

  nodes =
    if site ? nodes && builtins.isAttrs site.nodes then
      site.nodes
    else
      throw ''
        host-network:

        site.nodes missing for ${enterpriseName}.${siteName}
      '';

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
          host-network:

          invalid CIDR '${cidr}'
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
          host-network:

          cannot derive tenant VLAN from IPv4 CIDR '${cidr}'
        '';

  unitBelongsToHost =
    unitName:
      unitName == hostname
      || lib.hasPrefix "${hostname}-" unitName;

  localFabricUnits =
    builtins.filter unitBelongsToHost (builtins.attrNames inventoryFabric);

  unitPorts =
    unitName:
      let
        node = inventoryFabric.${unitName};
      in
      if node ? ports && builtins.isAttrs node.ports then
        node.ports
      else
        throw ''
          host-network:

          inventory.fabric.${unitName}.ports missing or not an attrset.
        '';

  tenantPortForUnit =
    unitName:
      let
        ports = unitPorts unitName;
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
          host-network:

          No tenant-facing inventory port found for unit '${unitName}'.

          inventory.fabric.${unitName}.ports:
          ${builtins.toJSON ports}
        '';

  tenantNameForUnit =
    unitName:
      (tenantPortForUnit unitName).attachment.name;

  nodeContextForUnit =
    unitName:
      if builtins.hasAttr unitName nodes then
        nodes.${unitName}
      else
        throw ''
          host-network:

          Missing CPM node context for unit '${unitName}'.
        '';

  tenantNetworkForUnit =
    unitName:
      let
        tenantName = tenantNameForUnit unitName;
        node = nodeContextForUnit unitName;
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
          host-network:

          CPM node '${unitName}' has no tenant network '${tenantName}'.

          Known node networks:
          ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames networks)}
        '';

  tenantVlanForUnit =
    unitName:
      parseTenantVlanFromIPv4CIDR (tenantNetworkForUnit unitName).ipv4;

  transitVlanForUnit =
    unitName:
      let
        ports = unitPorts unitName;
        transitPorts =
          builtins.filter (
            port:
              builtins.isAttrs port
              && (port ? link)
              && (port ? vlan)
          ) (attrValues ports);
      in
      if transitPorts != [ ] then
        (builtins.head transitPorts).vlan
      else
        throw ''
          host-network:

          No transit inventory port found for unit '${unitName}'.

          inventory.fabric.${unitName}.ports:
          ${builtins.toJSON ports}
        '';

  tenantVlans =
    lib.unique (
      map tenantVlanForUnit localFabricUnits
    );

  transitVlans =
    lib.unique (
      map transitVlanForUnit localFabricUnits
    );

  lanBridgeFor = vid: "br-lan-${toString vid}";
  lanVlanIfFor = vid: "${trunkParent}.${toString vid}";

  transitBridgeFor = vid: "br-tr-${toString vid}";
  transitVlanIfFor = vid: "${trunkParent}.${toString vid}";

  mgmtNetworkConfig = {
    Bridge = mgmtBridge;
    ConfigureWithoutCarrier = true;
  };

  mgmtBridgeNetworkConfig =
    {
      ConfigureWithoutCarrier = true;
    }
    //
    (
      if mgmtIPv4Mode == "dhcp" then
        { DHCP = "ipv4"; }
      else if mgmtIPv4Mode == "disabled" then
        { }
      else if mgmtIPv4Mode == "static" then
        { DHCP = "no"; }
      else
        { }
    )
    //
    (
      if mgmtIPv6Mode == "dhcp" then
        {
          DHCP = "yes";
          IPv6AcceptRA = true;
        }
      else if mgmtIPv6Mode == "ra-only" then
        {
          DHCP = "ipv4";
          IPv6AcceptRA = true;
        }
      else if mgmtIPv6Mode == "disabled" then
        {
          IPv6AcceptRA = false;
          LinkLocalAddressing = "ipv4";
        }
      else if mgmtIPv6Mode == "static" then
        {
          IPv6AcceptRA = false;
        }
      else
        { }
    );

  mgmtBridgeAddresses =
    []
    ++ (if mgmtIPv4Mode == "static" then
          map (addr: { Address = addr; }) (mgmtIPv4.addresses or [ ])
        else
          [ ])
    ++ (if mgmtIPv6Mode == "static" then
          map (addr: { Address = addr; }) (mgmtIPv6.addresses or [ ])
        else
          [ ]);

  mgmtBridgeRoutes =
    []
    ++ (if mgmtIPv4Mode == "static" && mgmtIPv4 ? gateway then
          [ { Gateway = mgmtIPv4.gateway; } ]
        else
          [ ])
    ++ (if mgmtIPv6Mode == "static" && mgmtIPv6 ? gateway then
          [ { Gateway = mgmtIPv6.gateway; } ]
        else
          [ ]);
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;

  systemd.network.netdevs =
    lib.mkMerge (
      [
        {
          "00-${mgmtBridge}" = {
            netdevConfig = {
              Name = mgmtBridge;
              Kind = "bridge";
            };
          };
        }
        {
          "01-${mgmtVlanIf}" = {
            netdevConfig = {
              Name = mgmtVlanIf;
              Kind = "vlan";
            };
            vlanConfig.Id = mgmtVlan;
          };
        }
      ]
      ++
      (map (vid: {
        "10-${lanBridgeFor vid}" = {
          netdevConfig = {
            Name = lanBridgeFor vid;
            Kind = "bridge";
          };
        };
      }) tenantVlans)
      ++
      (map (vid: {
        "11-${transitBridgeFor vid}" = {
          netdevConfig = {
            Name = transitBridgeFor vid;
            Kind = "bridge";
          };
        };
      }) transitVlans)
      ++
      (map (vid: {
        "20-${lanVlanIfFor vid}" = {
          netdevConfig = {
            Name = lanVlanIfFor vid;
            Kind = "vlan";
          };
          vlanConfig.Id = vid;
        };
      }) tenantVlans)
      ++
      (map (vid: {
        "21-${transitVlanIfFor vid}" = {
          netdevConfig = {
            Name = transitVlanIfFor vid;
            Kind = "vlan";
          };
          vlanConfig.Id = vid;
        };
      }) transitVlans)
    );

  systemd.network.networks =
    lib.mkMerge (
      [
        {
          "00-${trunkParent}" = {
            matchConfig.Name = trunkParent;
            networkConfig = {
              VLAN =
                [ mgmtVlanIf ]
                ++ (map lanVlanIfFor tenantVlans)
                ++ (map transitVlanIfFor transitVlans);
              ConfigureWithoutCarrier = true;
            };
          };
        }

        {
          "05-${mgmtVlanIf}" = {
            matchConfig.Name = mgmtVlanIf;
            networkConfig = mgmtNetworkConfig;
          };
        }

        {
          "06-${mgmtBridge}" = {
            matchConfig.Name = mgmtBridge;
            networkConfig = mgmtBridgeNetworkConfig;
            addresses = mgmtBridgeAddresses;
            routes = mgmtBridgeRoutes;
          };
        }
      ]
      ++
      (map (vid: {
        "30-${lanVlanIfFor vid}" = {
          matchConfig.Name = lanVlanIfFor vid;
          networkConfig = {
            Bridge = lanBridgeFor vid;
            ConfigureWithoutCarrier = true;
          };
        };
      }) tenantVlans)
      ++
      (map (vid: {
        "31-${transitVlanIfFor vid}" = {
          matchConfig.Name = transitVlanIfFor vid;
          networkConfig = {
            Bridge = transitBridgeFor vid;
            ConfigureWithoutCarrier = true;
          };
        };
      }) transitVlans)
      ++
      (map (vid: {
        "40-${lanBridgeFor vid}" = {
          matchConfig.Name = lanBridgeFor vid;
          networkConfig = {
            ConfigureWithoutCarrier = true;
          };
        };
      }) tenantVlans)
      ++
      (map (vid: {
        "41-${transitBridgeFor vid}" = {
          matchConfig.Name = transitBridgeFor vid;
          networkConfig = {
            ConfigureWithoutCarrier = true;
          };
        };
      }) transitVlans)
    );
}
