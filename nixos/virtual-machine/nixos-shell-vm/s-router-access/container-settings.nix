{
  config,
  pkgs,
  lib,
  vmRoot,
  outPath,
  ...
}:
{
  containers."${config.networking.hostName}-container" = {
    autoStart = true;
    privateNetwork = true;

    extraVeths = {
      lan.hostBridge = "br-lan-trunk";
    };

    bindMounts."/run/secrets" = {
      hostPath = "/run/secrets";
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
      };

    additionalCapabilities = [
      "CAP_BPF"
      "CAP_PERFMON"
      "CAP_NET_ADMIN"
      "CAP_SYS_ADMIN"
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
