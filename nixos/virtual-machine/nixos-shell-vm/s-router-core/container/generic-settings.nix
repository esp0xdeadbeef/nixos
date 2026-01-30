{ pkgs, lib, ...}:
{system.stateVersion = "25.11";

  services.resolved.enable = false;
  services.dbus.enable = true;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;

  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;
}
