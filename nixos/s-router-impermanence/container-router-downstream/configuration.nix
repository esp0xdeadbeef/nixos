{ pkgs, lib, ... }:
{

  imports = [
    ./debugging-packages.nix
    ./dns-dhcp.nix
    ./firewall.nix
    ./kernel.nix
    ./networkd.nix
    ./wan.nix
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

  networking.nat = {
    enable = true;
    externalInterface = "lan1010";
    internalInterfaces = [
      "lan2"
      "lan3"
      "lan10"
      "lan1000"
    ];
  };

}
