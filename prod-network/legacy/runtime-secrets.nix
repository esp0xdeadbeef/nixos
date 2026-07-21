{ config, ... }:

let
  inventoryRuntimeSecretFile = ./secrets/runtime.yaml;
  vlan2ReservationsFile = "/run/secrets/s-router-prod-vlan2-reservations.json";
  vlan3MacFile = "/run/secrets/s-nebula-container-mac";
in
{
  sops.secrets = {
    pppoe-username.sopsFile = inventoryRuntimeSecretFile;
    pppoe-password.sopsFile = inventoryRuntimeSecretFile;
    s-nebula-container-mac.sopsFile = inventoryRuntimeSecretFile;

    subnet-ipv6-vlan2 = {
      sopsFile = inventoryRuntimeSecretFile;
      key = "subnet-ipv6";
      owner = "root";
      mode = "0400";
    };

    subnet-ipv6-vlan3 = {
      sopsFile = inventoryRuntimeSecretFile;
      key = "subnet-ipv6";
      owner = "root";
      mode = "0400";
    };

    subnet-ipv6-vlan7 = {
      sopsFile = inventoryRuntimeSecretFile;
      key = "subnet-ipv6";
      owner = "root";
      mode = "0400";
    };

    s-router-prod-vlan2-reservations-json = {
      sopsFile = ./secrets/vlan2-hostnames-servers.json.age;
      format = "binary";
      path = vlan2ReservationsFile;
    };
  };

  containers.access-vlan2.bindMounts.${vlan2ReservationsFile} = {
    hostPath = config.sops.secrets.s-router-prod-vlan2-reservations-json.path;
    isReadOnly = true;
  };

  containers.access-vlan3.bindMounts.${vlan3MacFile} = {
    hostPath = config.sops.secrets.s-nebula-container-mac.path;
    isReadOnly = true;
  };
}
