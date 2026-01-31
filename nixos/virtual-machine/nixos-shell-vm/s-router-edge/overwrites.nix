{ config, lib, ... }:
{
  containers = lib.mkMerge [
    {
      "${config.networking.hostName}-container".bindMounts."/run/secrets" = {
        hostPath = "/run/secrets";
      };
    }
  ];

  sops.secrets.subnet-ipv6 = { };
}
