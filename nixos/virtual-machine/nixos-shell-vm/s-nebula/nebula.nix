{ lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [ nebula ];

  services.nebula.networks.mesh = {
    enable = true;
    isLighthouse = true;

    cert = "/persist/etc/nebula/beacon.crt";
    key = "/persist/etc/nebula/beacon.key";
    ca = "/persist/etc/nebula/ca.crt";
  };
  #users.groups.nebula = { };
  #users.users.nebula = {
  #  isSystemUser = true;
  #  group = "nebula";
  #};
  #users.groups.nebula-mesh = { };
  #users.users.nebula-mesh = {
  #  isSystemUser = true;
  #  group = "nebula";
  #};

}
