{
  config,
  pkgs,
  lib,
  ...
}:
{
  networking.networkmanager.enable = false;
  networking.useNetworkd = true;

  # Disable networkd-wait-online
  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;
}
