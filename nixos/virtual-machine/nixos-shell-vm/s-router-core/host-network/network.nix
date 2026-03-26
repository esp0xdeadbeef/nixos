{
  config,
  lib,
  ...
}:

let
  inventoryImported = import ../inventory.nix;
  inventory =
    if builtins.isFunction inventoryImported then
      inventoryImported { inherit lib; }
    else
      inventoryImported;

  hostname = config.networking.hostName;

  deploymentHosts =
    if inventory ? deployment
      && builtins.isAttrs inventory.deployment
      && inventory.deployment ? hosts
      && builtins.isAttrs inventory.deployment.hosts
    then
      inventory.deployment.hosts
    else
      throw "host-network: inventory.deployment.hosts missing";

  deploymentHostNames = lib.sort builtins.lessThan (builtins.attrNames deploymentHosts);

  deploymentHostName =
    if builtins.hasAttr hostname deploymentHosts then
      hostname
    else if builtins.length deploymentHostNames == 1 then
      builtins.head deploymentHostNames
    else
      throw ''
        host-network: missing host config

        current hostname:
        ${hostname}

        known deployment hosts:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ deploymentHostNames)}
      '';

  hostConfig = deploymentHosts.${deploymentHostName};

  uplinks =
    if hostConfig ? uplinks && builtins.isAttrs hostConfig.uplinks then
      hostConfig.uplinks
    else
      throw "host-network: hostConfig.uplinks missing";

  bridgeNetworks =
    if hostConfig ? bridgeNetworks && builtins.isAttrs hostConfig.bridgeNetworks then
      hostConfig.bridgeNetworks
    else
      { };

  realizationNodes =
    if inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      { };

  synthesizedTransitLinks =
    lib.unique (
      lib.concatMap (
        nodeName:
        let
          node = realizationNodes.${nodeName};
          ports =
            if node ? ports && builtins.isAttrs node.ports then
              node.ports
            else
              { };
        in
        if (node.host or null) == deploymentHostName then
          lib.concatMap (
            portName:
            let
              port = ports.${portName};
            in
            lib.optionals (
              builtins.isAttrs port
              && port ? link
              && builtins.isString port.link
              && port ? attach
              && builtins.isAttrs port.attach
              && (port.attach.kind or null) == "direct"
            ) [
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
        map (
          linkName:
          {
            name = linkName;
            value = {
              name = linkName;
            };
          }
        ) synthesizedTransitLinks
      );

  uplinkNames = lib.sort builtins.lessThan (builtins.attrNames uplinks);
  transitNames = lib.sort builtins.lessThan (builtins.attrNames transitBridges);

  bridgeNetworkFor =
    bridge:
    if builtins.hasAttr bridge bridgeNetworks then
      bridgeNetworks.${bridge}
    else
      { ConfigureWithoutCarrier = true; };

  transitNamesForUplink =
    uplinkName:
    lib.filter (
      transitName:
      let
        transit = transitBridges.${transitName};
      in
      (transit.parentUplink or null) == uplinkName
    ) transitNames;

  uplinkNetdevs = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        transitNamesOnUplink = transitNamesForUplink uplinkName;
        vlanIfName =
          if (uplink.mode or "") == "vlan" then
            "${uplink.parent}.${toString uplink.vlan}"
          else
            null;
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
    lib.concatMap (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        vlanIfName = "${uplink.parent}.${toString uplink.vlan}";
      in
      if (uplink.mode or "") == "vlan" then
        [
          {
            name = "20-${uplink.parent}-${uplinkName}";
            value = {
              matchConfig.Name = uplink.parent;
              networkConfig = {
                VLAN = [ vlanIfName ];
                ConfigureWithoutCarrier = true;
              };
            };
          }
          {
            name = "21-${vlanIfName}";
            value = {
              matchConfig.Name = vlanIfName;
              networkConfig = {
                Bridge = uplink.bridge;
                ConfigureWithoutCarrier = true;
              };
            };
          }
        ]
      else
        [
          {
            name = "20-${uplink.parent}-${uplinkName}";
            value = {
              matchConfig.Name = uplink.parent;
              networkConfig = {
                Bridge = uplink.bridge;
                ConfigureWithoutCarrier = true;
              };
            };
          }
        ]
    ) uplinkNames
  );

  uplinkBridgeNetworks = builtins.listToAttrs (
    map (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        transitNamesOnUplink = transitNamesForUplink uplinkName;
      in
      {
        name = "30-${uplink.bridge}";
        value = {
          matchConfig.Name = uplink.bridge;
          networkConfig =
            bridgeNetworkFor uplink.bridge
            // lib.optionalAttrs ((uplink.mode or "") == "trunk" && transitNamesOnUplink != [ ]) {
              VLAN = map (
                transitName:
                let
                  transit = transitBridges.${transitName};
                in
                "${uplink.bridge}.${toString transit.vlan}"
              ) transitNamesOnUplink;
            };
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
            networkConfig.ConfigureWithoutCarrier = true;
          };
        }
      ]
      ++ lib.optionals (parentUplink != null && builtins.hasAttr parentUplink uplinks && (uplinks.${parentUplink}.mode or "") == "trunk") [
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
              networkConfig = {
                Bridge = transit.name;
                ConfigureWithoutCarrier = true;
              };
            };
        }
      ]
    ) transitNames
  );
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;

  systemd.network.netdevs = uplinkNetdevs // transitNetdevs;
  systemd.network.networks = uplinkParentNetworks // uplinkBridgeNetworks // transitNetworks;
}
