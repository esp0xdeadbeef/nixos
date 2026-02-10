# ./container-settings.nix
# FILE: s-router-policy-only/container-settings.nix
{
  config,
  pkgs,
  lib,
  outPath,
  ...
}:

{
  containers."${config.networking.hostName}-container" = {
    autoStart = true;
    privateNetwork = true;

    # SINGLE, STABLE trunk into policy container
    extraVeths = {
      lan.hostBridge = "br-lan-trunk";
    };

    bindMounts."/persist" = {
      hostPath = "/persist";
      isReadOnly = false;
    };

    bindMounts."/run/secrets" = {
      hostPath = "/run/secrets";
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

    specialArgs = {
      inherit outPath;
    };

    config =
      { outPath, ... }:
      {
        imports = [
          ./container
        ];

        networking.useNetworkd = true;
        systemd.network.enable = true;
        networking.useDHCP = false;

        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
          "net.ipv6.conf.default.forwarding" = 1;
        };

        system.stateVersion = "25.11";
      };

    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_SYS_ADMIN"
      "CAP_NET_RAW"
      "CAP_BPF"
      "CAP_PERFMON"
    ];

    enableTun = true;
  };

  sops.secrets.subnet-ipv6 = { };

  sops.secrets.vlan2-hostnames-servers-json = {
    sopsFile = "${outPath}/secrets/vlan2-hostnames-servers.json.age";
    format = "binary";
    path = "/run/secrets/vlan2-hostnames-servers.json";
  };
}
