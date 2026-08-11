{ config, lib, relativeRepo, ... }:

{
  imports = [
    (relativeRepo.module "prod-network/current/runtime-secrets.nix")
  ];

  sops.secrets.subnet-ipv6-vlan8 = {
    sopsFile = ./secrets/runtime.yaml;
    key = "subnet-ipv6";
    owner = "root";
    mode = "0400";
  };
}
