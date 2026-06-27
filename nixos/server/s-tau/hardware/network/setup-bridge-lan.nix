{ config
, pkgs
, lib
, ...
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

  systemd.network.netdevs."15-vlan2" = {
    netdevConfig = {
      Name = "vlan2";
      Kind = "vlan";
    };
    vlanConfig.Id = 2;
  };

  ###### PHYSICAL NIC -> BRIDGE ######
  systemd.network.networks."10-eno3" = {
    matchConfig.Name = "eno3";
    networkConfig = {
      Bridge = "vmbr4";
      # Keep a host management address on VLAN 2 while eno3 remains the LAN
      # bridge port for VM traffic.
      VLAN = [ "vlan2" ];
    };
  };

  systemd.network.networks."20-vlan2" = {
    matchConfig.Name = "vlan2";
    networkConfig = {
      DHCP = "ipv4";
      LinkLocalAddressing = "no";
    };
    dhcpV4Config = {
      ClientIdentifier = "mac";
      SendRelease = false;
      MaxAttempts = "infinity";
      UseRoutes = false;
      UseGateway = false;
    };
  };

  ###### BRIDGE: NO IP, NO DHCP ######
  systemd.network.networks."10-vmbr4" = {
    matchConfig.Name = "vmbr4";
    networkConfig = { };
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
