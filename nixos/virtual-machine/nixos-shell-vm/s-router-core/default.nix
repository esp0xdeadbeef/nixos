{
  inputs,
  outPath,
  config,
  pkgs,
  lib,
  ...
}:

let
  api = inputs.network-renderer-nixos.lib;
  renderer = api.renderer;
  selectors = api.selectors;

  system = pkgs.stdenv.hostPlatform.system;
  hostName = config.networking.hostName;

  inventoryPath = builtins.toPath ../inventory.nix;
  intentPath = builtins.toPath "${outPath}/library/100-fabric-routing/inputs/intent.nix";

  selected = selectors.query {
    selector = hostName;
    inherit
      intentPath
      inventoryPath
      ;
    file = "s-router-core/default.nix";
  };

  intent = selected.fabricInputs;
  globalInventory = selected.globalInventory;
  hostContext = selected.hostContext;

  compilerOut = renderer.buildCompiler {
    inherit intent system;
  };

  forwardingOut = renderer.buildForwarding {
    inherit compilerOut system;
  };

  controlPlaneOut = renderer.buildControlPlane {
    inherit
      forwardingOut
      system
      ;
    inventory = globalInventory;
  };

  renderedHostNetwork = renderer.renderHostNetwork {
    hostName =
      if hostContext ? deploymentHostName && builtins.isString hostContext.deploymentHostName then
        hostContext.deploymentHostName
      else
        hostName;
    cpm = controlPlaneOut;
    inventory = globalInventory;
  };

  sanitizeContainer =
    containerName: container: {
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

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  sanitizedContainers = builtins.listToAttrs (
    map (containerName: {
      name = containerName;
      value = sanitizeContainer containerName renderedHostNetwork.containers.${containerName};
    }) (sortedAttrNames (renderedHostNetwork.containers or { }))
  );

  debugPayload = {
    inherit
      system
      hostName
      hostContext
      intent
      globalInventory
      compilerOut
      forwardingOut
      controlPlaneOut
      ;

    intentPath = builtins.toString intentPath;
    inventoryPath = builtins.toString inventoryPath;

    renderedHost = {
      hostName = renderedHostNetwork.hostName or null;
      deploymentHostName = renderedHostNetwork.deploymentHostName or null;
      runtimeRole = renderedHostNetwork.runtimeRole or null;
      selectedUnits = renderedHostNetwork.selectedUnits or [ ];
      selectedRoleNames = renderedHostNetwork.selectedRoleNames or [ ];
      bridgeNameMap = renderedHostNetwork.bridgeNameMap or { };
      bridges = renderedHostNetwork.bridges or { };
      netdevs = renderedHostNetwork.netdevs or { };
      networks = renderedHostNetwork.networks or { };
      attachTargets = renderedHostNetwork.attachTargets or [ ];
      localAttachTargets = renderedHostNetwork.localAttachTargets or [ ];
      uplinks = renderedHostNetwork.uplinks or { };
      transitBridges = renderedHostNetwork.transitBridges or { };
      containers = sanitizedContainers;
      debug = renderedHostNetwork.debug or { };
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
    inherit
      globalInventory
      hostContext
      intent
      compilerOut
      forwardingOut
      controlPlaneOut
      renderedHostNetwork
      ;
  };

  environment.etc."network-renderer/network-renderer-nixos.json".text =
    builtins.toJSON debugPayload;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = lib.mkForce false;

  systemd.network.netdevs = renderedHostNetwork.netdevs or { };
  systemd.network.networks = renderedHostNetwork.networks or { };

  containers = renderedHostNetwork.containers or { };
}
