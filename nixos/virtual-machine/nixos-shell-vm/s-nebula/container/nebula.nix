{ lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    nebula
    tcpdump
  ];

  services.nebula.networks.mesh = {
    enable = true;
    isLighthouse = true;

    cert = "/persist/etc/nebula/beacon.crt";
    key = "/persist/etc/nebula/beacon.key";
    ca = "/persist/etc/nebula/ca.crt";

  };
}
