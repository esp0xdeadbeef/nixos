{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  systemd.services."container@${config.networking.hostName}-container".serviceConfig = {
    TasksMax = "infinity";
    TimeoutStartSec = lib.mkForce "16min";
  };
  containers."${config.networking.hostName}-container" = {
    autoStart = true;
    privateNetwork = true;
    extraVeths = {
      veth2.hostBridge = "vlan7";
      #veth3.hostBridge = "vlan3";
      #veth4.hostBridge = "vlan4";
      #veth5.hostBridge = "vlan5";
      #veth6.hostBridge = "vlan6";
      #veth7.hostBridge = "vlan7";
      #veth8.hostBridge = "vlan8";
      #veth9.hostBridge = "vlan9";
    };

    bindMounts."/persist" = {
      hostPath = "/persist"; # ← folder on the HOST
      isReadOnly = false; # change to true if you want it read-only
    };
    config = ../container;
    additionalCapabilities = [
      "CAP_BPF"
      "CAP_PERFMON"
      "CAP_NET_ADMIN"
      "CAP_SYS_ADMIN"
    ];
  };
}
