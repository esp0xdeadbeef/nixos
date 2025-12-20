{ lib, pkgs, ... }:
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  # If you don't want wait-online blocking boot (common for routers)
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

}
