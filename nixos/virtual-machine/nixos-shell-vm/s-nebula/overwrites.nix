{ config, lib, ... }:
{
  containers."${config.networking.hostName}-container".extraVeths = lib.mkForce {
    veth0.hostBridge = "vlan2";
  };
  environment.persistence."/persist".directories = [
    {
      directory = "/etc/nebula";
      user = "root";
      group = "nebula-mesh";
      mode = "0750";
    }
  ];
  systemd.services."container@${config.networking.hostName}-container".serviceConfig.SystemCallFilter =
    lib.mkForce [ ];
  #containers."${config.networking.hostName}-container".enableTun = lib.mkDefault true;

  #users.groups.nebula-mesh = { };
  #users.users.nebula-mesh = {
  #  isSystemUser = true;
  #  group = "nebula-mesh";
  #};
  #systemd.tmpfiles.rules = [
  #  "f /etc/nebula/ca.crt 0644 root nebula-mesh -"
  #  "f /etc/nebula/lighthouse.crt 0644 root nebula-mesh -"
  #  "f /etc/nebula/lighthouse.key 0640 root nebula-mesh -"
  #];

}
