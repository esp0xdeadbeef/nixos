{
  config,
  pkgs,
  lib,
  vmRoot,
  ...
}:
{
  systemd.services."container@${config.networking.hostName}-container".serviceConfig = {
    TasksMax = "infinity";
    TimeoutStartSec = lib.mkForce "15min";
    ExecStartPre = [
      "${pkgs.coreutils}/bin/sleep 10"
    ];
  };

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

    # This is the key line:
    # Resolves to /nix/store/...-source/nixos/virtual-machine/nixos-shell-vm/s-test/container
    config = vmRoot + "/container";

    additionalCapabilities = [
      "CAP_BPF"
      "CAP_PERFMON"
      "CAP_NET_ADMIN"
      "CAP_SYS_ADMIN"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /persist/var/lib/containers 0755 root root -"
  ];
}

