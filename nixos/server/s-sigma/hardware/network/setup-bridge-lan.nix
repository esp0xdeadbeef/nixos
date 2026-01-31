{
  config,
  pkgs,
  lib,
  ...
}:

{
  networking.networkmanager.enable = lib.mkForce false;
  systemd.network.enable = true;

  ###### PURE L2 BRIDGE ######
  systemd.network.netdevs."10-vmbr4" = {
    netdevConfig = {
      Name = "vmbr4";
      Kind = "bridge";
    };

  };

  ###### PHYSICAL NIC -> BRIDGE ######
  systemd.network.networks."10-eno3" = {
    matchConfig.Name = "eno3";
    networkConfig = {
      Bridge = "vmbr4";
    };
  };

  ###### BRIDGE: NO IP, NO DHCP ######
  systemd.network.networks."10-vmbr4" = {
    matchConfig.Name = "vmbr4";
    networkConfig = {
    };
  };

  ###### LIBVIRT ######
  virtualisation.libvirtd = {
    enable = true;
    allowedBridges = [
      "vmbr4"
      "vmbr1"
    ];
  };

  ###### REQUIRED FOR BRIDGED TRAFFIC ######
  networking.firewall.checkReversePath = false;
}
