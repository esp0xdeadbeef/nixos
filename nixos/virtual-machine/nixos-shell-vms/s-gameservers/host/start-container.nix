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
    #extraVeths = {
    #  "net0".hostBridge = "br-vlan6";
    #};
    hostBridge = "vlan7";

    bindMounts."/persist/game-servers" = {
      hostPath = "/persist/game-servers"; # ← folder on the HOST
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
  systemd.tmpfiles.rules = [
    "d /persist/game-servers 0755 root root -"
  ];
}
