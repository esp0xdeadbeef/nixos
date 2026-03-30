{
  inputs,
  outPath,
  lib,
  ...
}:

let
  api = inputs.network-renderer-nixos.lib;

  moduleHostName = builtins.baseNameOf (builtins.toString ./.);

  containerSelection = {
    "s-router-core-wan" = true;
  };

  hostBuild = api.hostBuild {
    inherit
      lib
      outPath
      ;
    hostName = moduleHostName;
    inventoryPath = ../inventory.nix;
    selectorFile = "s-router-core/default.nix";
    containerSelection = containerSelection;
  };

  extraContainerOptions = {
    "*" = {
      autoStart = true;
    };

    "s-router-core-wan" = {
      additionalCapabilities = [ "NET_ADMIN" ];
    };
  };

  mergeContainer =
    name: rendered:
    let
      global = extraContainerOptions."*" or { };
      named = extraContainerOptions.${name} or { };
    in
    lib.recursiveUpdate (lib.recursiveUpdate rendered global) named;

  containers =
    lib.mapAttrs mergeContainer (hostBuild.renderedHostNetwork.containers or { });

  _validatedContainers =
    if builtins.attrNames containers != [ ] then
      true
    else
      throw ''
        s-router-core/default.nix: no containers were rendered for host '${moduleHostName}'

        containerSelection:
        ${builtins.toJSON containerSelection}

        rendered container names:
        ${builtins.toJSON (builtins.attrNames (hostBuild.renderedHostNetwork.containers or { }))}

        selected units:
        ${builtins.toJSON (hostBuild.renderedHostNetwork.selectedUnits or [ ])}

        selected roles:
        ${builtins.toJSON (hostBuild.renderedHostNetwork.selectedRoleNames or [ ])}
      '';
in
builtins.seq _validatedContainers {
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./mount-utils.nix
    ./sops.nix
  ];

  system.stateVersion = lib.mkForce "24.11";

  _module.args = hostBuild.moduleArgs or { };

  environment.etc."network-renderer/network-renderer-nixos.json".text =
    builtins.toJSON (hostBuild.debugPayload or { });

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = lib.mkForce false;

  systemd.network.netdevs = hostBuild.renderedHostNetwork.netdevs or { };
  systemd.network.networks = hostBuild.renderedHostNetwork.networks or { };
  containers = containers;
}
