{
  config,
  pkgs,
  lib,
  vmRoot,
  ...
}:
{
  containers."${config.networking.hostName}-container" = {
    autoStart = true;
    privateNetwork = true;

    bindMounts."/persist" = {
      hostPath = "/persist";
      isReadOnly = false;
    };
    # podman
    bindMounts."/var/lib/containers" = {
      hostPath = "/persist-state/var/lib/containers";
      isReadOnly = false;
    };
    # docker:
    bindMounts."/var/lib/docker" = {
      hostPath = "/persist-state/var/lib/docker";
      isReadOnly = false;
    };

    # This is the key line:
    # Resolves to /nix/store/...-source/nixos/virtual-machine/nixos-shell-vm/{container-host}/container
    config = vmRoot + "/container";

    additionalCapabilities = [
      "CAP_BPF"
      "CAP_PERFMON"
      "CAP_NET_ADMIN"
      "CAP_SYS_ADMIN"
    ];
    enableTun = true;
  };
}
