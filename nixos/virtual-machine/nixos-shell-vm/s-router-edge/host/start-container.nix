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
  TimeoutStartSec = lib.mkForce "15min";
};
  containers."${config.networking.hostName}-container" = {
    autoStart = true;
    privateNetwork = true;
    extraVeths = {
       #veth2.hostBridge = "vlan2";
       #veth3.hostBridge = "vlan3";
       #veth4.hostBridge = "vlan4";
       #veth5.hostBridge = "vlan5";
       #veth6.hostBridge = "vlan6";
       lan3.hostBridge = "vlan3";
       lan7.hostBridge = "vlan7";
       lan1010.hostBridge = "vlan1010";
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
