{ inputs
, outPath
, lib
, ...
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
    inventoryPath = ../inventory.nix;
  };

  sliceArgs = {
    inherit (identity) enterpriseName siteName boxName;
    inherit (fabric) intentPath inventoryPath;
  };

  disabledContainers = { };

  commonContainerOptions = {
    autoStart = true;
    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
    ];
  };

  builtHost = api.renderer.buildHostFromPaths {
    inherit (fabric) intentPath inventoryPath;
    selector = identity.boxName;
    containerDefaults = commonContainerOptions;
    disabled = disabledContainers;
    file = "nixos/virtual-machine/nixos-shell-vm/s-router-access/default.nix";
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

  renderedHost = builtHost.renderedHost or { };

  renderedContainers = renderedHost.containers or { };

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
    bridgeNameMap = renderedHost.bridgeNameMap or { };
    bridges = renderedHost.bridges or { };
    netdevs = renderedHost.netdevs or { };
    networks = renderedHost.networks or { };
    containers = renderedContainers;
    debug = {
      host = renderedHost.debug or { };
      bridges = renderedHost.debug or { };
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
      inherit identity fabric disabledContainers;
      host = renderedHost.debug or { };
      bridges = renderedHost.debug or { };
      containers = builtins.attrNames renderedContainers;
    };

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = lib.mkForce false;

  systemd.network.netdevs = renderedHost.netdevs or { };

  systemd.network.networks = renderedHost.networks or { };

  containers = renderedContainers;
}
