{ config
, pkgs
, lib
, vmRoot
, relativeRepo
, ...
}:
{
  containers."${config.networking.hostName}-container" = {
    autoStart = true;
    privateNetwork = true;

    extraVeths = {
      veth2.hostBridge = "vlan2";
      veth3.hostBridge = "vlan3";
      veth4.hostBridge = "vlan4";
      veth5.hostBridge = "vlan5";
      veth6.hostBridge = "vlan6";
      veth7.hostBridge = "vlan7";
      veth8.hostBridge = "vlan8";
      veth9.hostBridge = "vlan9";
    };

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
    specialArgs = {
      inherit relativeRepo;
      # you can also pass inputs/self/outputs/etc if you want
      # inherit inputs self outputs;
    };

    config =
      { ... }:
      {
        imports = [
          ./container-default.nix
        ];
      };

    additionalCapabilities = [
      "CAP_BPF"
      "CAP_PERFMON"
      "CAP_NET_ADMIN"
      "CAP_SYS_ADMIN"
    ];
    enableTun = true;
  };
}
