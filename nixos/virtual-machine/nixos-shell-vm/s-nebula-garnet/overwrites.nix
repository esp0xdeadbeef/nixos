{ config, lib, ... }:
{
  sops.secrets.s-nebula-garnet-container-mac = { };

  containers."${config.networking.hostName}-container" = {
    extraVeths = lib.mkForce {
      veth0.hostBridge = "vlan3";
    };
    bindMounts."/run/secrets/s-nebula-garnet-container-mac" = {
      hostPath = config.sops.secrets.s-nebula-garnet-container-mac.path;
      isReadOnly = true;
    };
  };
  environment.persistence."/persist".directories = [
    {
      directory = "/etc/nebula";
      user = "root";
      group = "nebula-garnet";
      mode = "0750";
    }
  ];
  systemd.services."container@${config.networking.hostName}-container".serviceConfig.SystemCallFilter =
    lib.mkForce [ ];
}
