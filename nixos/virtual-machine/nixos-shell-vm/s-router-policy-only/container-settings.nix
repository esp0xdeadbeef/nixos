{
  config,
  pkgs,
  lib,
  outPath,
  controlPlaneOut,
  ...
}:

let
  hostname = config.networking.hostName;
  containerName = "${hostname}-container";

  inventory = import ./inventory.nix { inherit lib outPath; };

  nodeName =
    let
      nodeNames = builtins.attrNames inventory.realization.nodes;
      matches = lib.filter (n: inventory.realization.nodes.${n}.host == hostname) nodeNames;
    in
    if matches == [ ] then
      abort "container-settings.nix: no realization node found for host '${hostname}'"
    else if builtins.length matches > 1 then
      abort "container-settings.nix: multiple realization nodes found for host '${hostname}': ${lib.concatStringsSep ", " matches}"
    else
      builtins.head matches;

  renderedContainer = import ./lib/renderer/render-containers.nix {
    inherit lib inventory;
    inherit nodeName;
    hostName = hostname;
    cpm = controlPlaneOut;
  };
in
{
  containers.${containerName} = {
    autoStart = true;

    privateNetwork = true;
    hostBridge = null;

    extraVeths = renderedContainer.extraVeths;

    bindMounts."/persist" = {
      hostPath = "/persist";
      isReadOnly = false;
    };

    bindMounts."/run/secrets" = {
      hostPath = "/run/secrets";
      isReadOnly = true;
    };

    bindMounts."/var/lib/containers" = {
      hostPath = "/persist-state/var/lib/containers";
      isReadOnly = false;
    };

    bindMounts."/var/lib/docker" = {
      hostPath = "/persist-state/var/lib/docker";
      isReadOnly = false;
    };

    specialArgs = {
      inherit outPath controlPlaneOut;
    };

    config = { outPath, controlPlaneOut, ... }: {
      imports = [
        ./container
      ];

      _module.args = {
        inherit controlPlaneOut;
      };

      networking.useNetworkd = true;
      systemd.network.enable = true;
      networking.useDHCP = false;

      system.stateVersion = "25.11";
    };

    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_SYS_ADMIN"
      "CAP_NET_RAW"
      "CAP_BPF"
      "CAP_PERFMON"
    ];

    enableTun = true;
  };

  sops.secrets.subnet-ipv6 = { };
}
