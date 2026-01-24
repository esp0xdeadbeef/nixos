{ pkgs, lib, ... }:
{

  imports = [
    ./debugging-packages.nix
    ./kea-dhcp.nix
    ./firewall.nix
    ./kernel.nix
    ./networkd.nix
    ./wan.nix
    ./unbound.nix
    ./radvd.nix
    ./debug-packages.nix
  ];

  services.resolved.enable = false;

  system.stateVersion = "25.11";

  services.dbus.enable = true;
  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  systemd.tmpfiles.rules = [
    "d /run/kea 0777 root root -"
    "d /var/lib/kea 0777 root root -"
    "d /etc/ppp/peers/ 0777 root root -"
  ];

  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;

  networking.useHostResolvConf = lib.mkForce false;

  networking.useNetworkd = true;

  networking.useDHCP = false;

}
