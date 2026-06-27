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
  systemd.network.netdevs."10-vmbr1" = {
    netdevConfig = {
      Name = "vmbr1";
      Kind = "bridge";
    };
  };

  ###### PHYSICAL NIC -> BRIDGE ######
  systemd.network.networks."10-eno1" = {
    matchConfig.Name = "eno1";
    networkConfig = {
      Bridge = "vmbr1";
    };
  };

  ###### BRIDGE: NO IP, NO DHCP ######
  systemd.network.networks."10-vmbr1" = {
    matchConfig.Name = "vmbr1";
    networkConfig = {
    };
  };

  ###### LIBVIRT ######
  virtualisation.libvirtd = {
    enable = true;
    allowedBridges = [ "vmbr1" ];
  };

  ###### REQUIRED FOR BRIDGED TRAFFIC ######
  networking.firewall.checkReversePath = false;
}
