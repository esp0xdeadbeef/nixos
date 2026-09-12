{ config, ... }:

let
  inventoryRuntimeSecretFile = ./secrets/runtime.yaml;
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

    subnet-ipv6-vlan8 = {
      sopsFile = inventoryRuntimeSecretFile;
      key = "subnet-ipv6";
      owner = "root";
      mode = "0400";
    };
  };
}
