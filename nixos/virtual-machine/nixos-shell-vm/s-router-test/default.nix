{
  inputs,
  outPath,
  lib,
  ...
}:

let
  api = inputs.network-renderer-nixos.lib;

  identity = {
    enterpriseName = "esp0xdeadbeef";
    siteName = "site-a";
    boxName = builtins.baseNameOf (builtins.toString ./.);
  };

  fabric = {
    intentPath = "${outPath}/library/100-fabric-routing/inputs/intent.nix";
    inventoryPath = ./inventory.nix;
  };

  inventory = import ./inventory.nix;
  renderHostDefs = inventory.render.hosts or { };

  disabledContainers = { };

  commonContainerOptions = {
    autoStart = true;
  };

  sliceArgs = {
    inherit (identity) enterpriseName siteName boxName;
    inherit (fabric) intentPath inventoryPath;
  };

  builtHost = api.renderer.buildHostFromPaths {
    inherit (fabric) intentPath inventoryPath;
    selector = identity.boxName;
    file = "nixos/virtual-machine/nixos-shell-vm/s-router-test/default.nix";
  };

  resolvedHostContext =
    (builtHost.hostContext or { })
    // {
      hostname = identity.boxName;
      enterpriseName = identity.enterpriseName;
      siteName = identity.siteName;
      matchedEnterprises = [ identity.enterpriseName ];
      matchedSites = [ identity.siteName ];
    };

  renderedHost = api.host.build sliceArgs;
  renderedBridges = api.bridges.build sliceArgs;

  selectedRenderHostNames =
    lib.filter
      (renderHostName:
        let
          cfg = renderHostDefs.${renderHostName} or { };
          deploymentTarget =
            if builtins.isAttrs cfg && cfg ? deploymentHost && builtins.isString cfg.deploymentHost
            then cfg.deploymentHost
            else renderHostName;
        in
        deploymentTarget == identity.boxName
      )
      (builtins.attrNames renderHostDefs);

  renderedContainersByRenderHost =
    builtins.listToAttrs (
      map
        (renderHostName: {
          name = renderHostName;
          value = api.containers.buildForBox {
            inherit (identity) enterpriseName siteName;
            boxName = renderHostName;
            inherit (fabric) intentPath inventoryPath;
            disabled = disabledContainers;
            defaults = commonContainerOptions;
          };
        })
        selectedRenderHostNames
    );

  renderedContainers =
    lib.foldl'
      (acc: renderHostName: acc // renderedContainersByRenderHost.${renderHostName})
      { }
      selectedRenderHostNames;

  deploymentHostName =
    let
      fromBuiltHost =
        if
          builtHost ? hostContext
          && builtins.isAttrs builtHost.hostContext
          && builtHost.hostContext ? deploymentHostName
          && builtins.isString builtHost.hostContext.deploymentHostName
        then
          builtHost.hostContext.deploymentHostName
        else
          null;
    in
    if fromBuiltHost != null then fromBuiltHost else renderedHost.deploymentHostName or null;

  renderedHostNetwork = {
    hostName = renderedHost.hostName or identity.boxName;
    inherit deploymentHostName;
    bridgeNameMap = renderedBridges.bridgeNameMap or { };
    bridges = renderedBridges.bridges or { };
    netdevs =
      (renderedHost.netdevs or { })
      // (renderedBridges.netdevs or { });
    networks =
      (renderedHost.networks or { })
      // (renderedBridges.networks or { });
    containers = renderedContainers;
    debug = {
      host = renderedHost.debug or { };
      bridges = renderedBridges.debug or { };
      selectedRenderHostNames = selectedRenderHostNames;
      containersByRenderHost =
        lib.mapAttrs (_: value: builtins.attrNames value) renderedContainersByRenderHost;
      containers = builtins.attrNames renderedContainers;
    };
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
    inherit identity fabric;
    globalInventory = builtHost.globalInventory or { };
    hostContext = resolvedHostContext;
    intent = builtHost.fabricInputs or { };
    fabricInputs = builtHost.fabricInputs or { };
    compilerOut = builtHost.compilerOut or { };
    forwardingOut = builtHost.forwardingOut or { };
    controlPlaneOut = builtHost.controlPlaneOut or { };
    inherit renderedHostNetwork;
  };

  environment.etc."network-renderer/network-renderer-nixos.json".text =
    builtins.toJSON {
      inherit identity fabric disabledContainers selectedRenderHostNames;
      host = renderedHost.debug or { };
      bridges = renderedBridges.debug or { };
      containers = builtins.attrNames renderedContainers;
      containersByRenderHost =
        lib.mapAttrs (_: value: builtins.attrNames value) renderedContainersByRenderHost;
    };

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = lib.mkForce false;

  systemd.network.netdevs =
    (renderedHost.netdevs or { })
    // (renderedBridges.netdevs or { });

  systemd.network.networks =
    (renderedHost.networks or { })
    // (renderedBridges.networks or { });

  containers = renderedContainers;
  environment.etc."network-artifacts/control-plane-model.json".text = builtins.toJSON builtHost.controlPlaneOut;
}
