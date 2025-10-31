{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.nixos-router.enable = true;

  # Example minimal config
  services.nixos-router.interfaces = {
    wan = "eth0";
    lan = "br0";
  };

  networking.bridges.br0.interfaces = [ "eth1" ];
}
