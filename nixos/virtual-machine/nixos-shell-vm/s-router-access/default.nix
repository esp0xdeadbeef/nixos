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
    inventoryPath = ../inventory.nix;
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

  renderedHost = api.host.build {
    inherit lib outPath;
    inherit (identity) enterpriseName siteName boxName;
    inherit (fabric) intentPath inventoryPath;
  };

  renderedBridges = api.bridges.build {
    inherit lib outPath;
    inherit (identity) enterpriseName siteName boxName;
    inherit (fabric) intentPath inventoryPath;
  };

  renderedContainers = api.containers.buildForBox {
    inherit lib outPath;
    inherit (identity) enterpriseName siteName boxName;
    inherit (fabric) intentPath inventoryPath;

    disabled = disabledContainers;
    defaults = commonContainerOptions;
  };

  renderedHostNetwork = {
    hostName = renderedHost.hostName or identity.boxName;
    deploymentHostName = renderedHost.deploymentHostName or null;
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
      bridges = renderedBridges.debug or { };
      containers = builtins.attrNames renderedContainers;
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
}
