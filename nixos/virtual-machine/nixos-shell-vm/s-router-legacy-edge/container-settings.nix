{ config
, pkgs
, lib
, vmRoot
, relativeRepo
, ...
}:
{
  containers."${config.networking.hostName}-container" = {
    autoStart = true;
    privateNetwork = true;

    extraVeths = {
      lan.hostBridge = "br-lan-trunk";
    };

    bindMounts."/persist" = {
      hostPath = "/persist";
      isReadOnly = false;
    };
    bindMounts."/run/secrets" = {
      hostPath = "/run/secrets";
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
      inherit relativeRepo;
    };

    config =
      { ... }:
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
    sopsFile = relativeRepo.sourcePath "secrets/vlan2-hostnames-servers.json.age";
    format = "binary";
    path = "/run/secrets/vlan2-hostnames-servers.json";
  };

}
