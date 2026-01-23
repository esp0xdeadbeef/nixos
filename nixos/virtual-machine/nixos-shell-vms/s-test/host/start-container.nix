{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
systemd.services."container@s-test-container".serviceConfig = {
  TasksMax = "infinity";
  TimeoutStartSec = lib.mkForce "15min";
};
  containers."s-test-container" = {
    autoStart = true;
    privateNetwork = true;
    #extraVeths = {
    #  "net0".hostBridge = "vlan6";
    #};
    extraVeths = {
       veth-vlan2.hostBridge = "vlan2";
       veth-vlan3.hostBridge = "vlan3";
       veth-vlan4.hostBridge = "vlan4";
       veth-vlan5.hostBridge = "vlan5";
       veth-vlan6.hostBridge = "vlan6";
       veth-vlan7.hostBridge = "vlan7";
       veth-vlan8.hostBridge = "vlan8";
       veth-vlan9.hostBridge = "vlan9";
    };

    #bindMounts."/persist" = {
    #  hostPath = "/persist"; # ← folder on the HOST
    #  isReadOnly = false; # change to true if you want it read-only
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
