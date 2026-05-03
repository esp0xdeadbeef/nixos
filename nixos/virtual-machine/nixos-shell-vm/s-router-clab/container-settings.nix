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
    hostAddress = "10.233.222.1";
    localAddress = "10.233.222.2";

    extraVeths = {
      veth2.hostBridge = "vlan2";
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

  networking.firewall.allowedTCPPorts = [ 2222 ];

  systemd.sockets.s-router-clab-container-ssh = {
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "0.0.0.0:2222" ];
  };

  systemd.services.s-router-clab-container-ssh = {
    requires = [ "container@${config.networking.hostName}-container.service" ];
    after = [ "container@${config.networking.hostName}-container.service" ];
    serviceConfig.ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 10.233.222.2:22";
  };
}
