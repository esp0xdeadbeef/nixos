{
  inputs,
  lib,
  outPath,
  ...
}:

let
  system = "x86_64-linux";
  hostName = "s-router-policy";

  fabric = {
    intentPath = "${outPath}/library/100-fabric-routing/inputs/intent.nix";
    inventoryPath = "${outPath}/nixos/virtual-machine/nixos-shell-vm/inventory.nix";
  };

  cpmBuilt = inputs.network-control-plane-model.libBySystem.${system}.compileAndBuildFromPaths {
    inputPath = fabric.intentPath;
    inherit (fabric) inventoryPath;
  };

  builtHost = inputs.network-renderer-nixos.libBySystem.${system}.renderer.buildHostFromControlPlane {
    controlPlaneOut = cpmBuilt;
    selector = hostName;
    inherit system;
    containerDefaults = {
      autoStart = true;
      additionalCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };
    disabled = { };
    file = "nixos/virtual-machine/nixos-shell-vm/${hostName}/default.nix";
  };

  renderedHost = builtHost.renderedHost or { };
  renderedContainers = renderedHost.containers or { };
  renderedHostNetwork = renderedHost // {
    containers = renderedContainers;
  };
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    builtHost.artifactModule
    ./mount-utils.nix
    ./sops.nix
  ];

  system.stateVersion = lib.mkForce "24.11";

  _module.args = {
    inherit fabric;
    globalInventory = builtHost.globalInventory or { };
    hostContext = builtHost.hostContext or { };
    intent = builtHost.fabricInputs or { };
    fabricInputs = builtHost.fabricInputs or { };
    compilerOut = builtHost.compilerOut or { };
    forwardingOut = builtHost.forwardingOut or { };
    controlPlaneOut = builtHost.controlPlaneOut or { };
    inherit renderedHostNetwork;
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
