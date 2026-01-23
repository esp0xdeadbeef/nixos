{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  containers."container-gameservers" = {
    autoStart = true;
    privateNetwork = true;

    extraVeths = {
      veth-vlan7.hostBridge = "vlan7";
    };

    bindMounts."/persist/game-servers" = {
      hostPath = "/persist/game-servers";
      isReadOnly = false;
    };

    #bindMounts."/var/lib/containers" = {
    #  hostPath = "/persist/var/lib/containers";
    #  isReadOnly = false;
    #};

    config = ../container;
    additionalCapabilities = [
      "CAP_BPF"
      "CAP_PERFMON"
      "CAP_NET_ADMIN"
      "CAP_SYS_ADMIN"
    ];

  };
}
