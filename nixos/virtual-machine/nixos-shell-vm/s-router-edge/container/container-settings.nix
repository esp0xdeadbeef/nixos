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

    extraVeths = {
      veth2.hostBridge = "vlan2";
      veth3.hostBridge = "vlan3";
      veth4.hostBridge = "vlan4";
      veth5.hostBridge = "vlan5";
      veth6.hostBridge = "vlan6";
      veth7.hostBridge = "vlan7";
      veth8.hostBridge = "vlan8";
      veth9.hostBridge = "vlan9";
      veth1010.hostBridge = "vlan1010";
    };

    bindMounts."/persist" = {
      hostPath = "/persist";
      isReadOnly = false;
    };

    # <<< ONLY SHARED RUNTIME STATE >>>
    bindMounts."/shared/dns-runtime" = {
      hostPath = "/var/run/dns-runtime";
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

