{
  config,
  pkgs,
  lib,
  ...
}:
{
  networking.networkmanager.enable = lib.mkForce false;
  networking.useNetworkd = true;

  networking.useDHCP = false;

  # Disable networkd-wait-online
  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;
}
