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
  hostName = hostname;
  containerName = "${hostname}-container";

  runtimeTargets =
    controlPlaneOut.control_plane_model.runtime.targets or { };

  nodeName =
    if lib.hasAttr hostname runtimeTargets then
      hostname
    else
      abort "container-settings.nix: runtime target '${hostname}' missing";

  renderedContainer = import ./lib/renderer/render-containers.nix {
    inherit lib;
    inventory = controlPlaneOut;
    inherit nodeName hostName;
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

    config = { controlPlaneOut, ... }: {
      imports = [
        ./container
      ];

      _module.args = {
        inherit controlPlaneOut;
      };

      networking.useNetworkd = true;
      systemd.network.enable = true;
      networking.useDHCP = false;
      networking.useHostResolvConf = false;
      services.resolved.enable = lib.mkForce false;

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
