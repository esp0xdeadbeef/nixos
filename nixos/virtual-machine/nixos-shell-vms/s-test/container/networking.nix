{ lib, ... }:

{
  networking.networkmanager.enable = true;

  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;
}
