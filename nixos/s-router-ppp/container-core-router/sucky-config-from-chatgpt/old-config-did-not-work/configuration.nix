### FILE: ./configuration.nix ###
{ pkgs, lib, ... }:
{
  imports = [
    ./wan.nix
    ./debugging-packages.nix
    ./firewall.nix
    ./downstream.nix
    ./kernel.nix

    # generate /run/radvd.conf and /run/kea-dhcp6.conf from the ISP PD
    ./pd-generate.nix

    # real services
    ./radvd.nix
    ./kea-dhcp6.nix
  ];

  system.stateVersion = "25.11";

  services.resolved.enable = false;
  services.dbus.enable = true;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;

  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;
}

