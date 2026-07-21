{ config, ... }:

let
  inventoryRuntimeSecretFile = ./secrets/runtime.yaml;
  vlan2ReservationsFile = "/run/secrets/s-router-prod-vlan2-reservations.json";
  vlan2ReservationNamesFile = "/run/secrets/s-router-prod-vlan2-reservation-names.json";
  vlan3ReservationsFile = "/run/secrets/s-router-prod-vlan3-reservations.json";
in
{
  sops.secrets = {
    pppoe-username.sopsFile = inventoryRuntimeSecretFile;
    pppoe-password.sopsFile = inventoryRuntimeSecretFile;

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
      sopsFile = ./secrets/vlan2-reservations.json.age;
      format = "binary";
      path = vlan2ReservationsFile;
    };

    s-router-prod-vlan2-reservation-names-json = {
      sopsFile = ./secrets/vlan2-reservation-names.json.age;
      format = "binary";
      path = vlan2ReservationNamesFile;
    };

    s-router-prod-vlan3-reservations-json = {
      sopsFile = ./secrets/vlan3-reservations.json.age;
      format = "binary";
      path = vlan3ReservationsFile;
    };
  };

  containers.access-vlan2.bindMounts = {
    ${vlan2ReservationsFile} = {
      hostPath = config.sops.secrets.s-router-prod-vlan2-reservations-json.path;
      isReadOnly = true;
    };

    ${vlan2ReservationNamesFile} = {
      hostPath = config.sops.secrets.s-router-prod-vlan2-reservation-names-json.path;
      isReadOnly = true;
    };
  };

  containers.access-vlan3.bindMounts.${vlan3ReservationsFile} = {
    hostPath = config.sops.secrets.s-router-prod-vlan3-reservations-json.path;
    isReadOnly = true;
  };
}
