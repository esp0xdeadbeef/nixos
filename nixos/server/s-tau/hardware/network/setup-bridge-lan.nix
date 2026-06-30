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
      MACAddress = "14:18:77:44:5d:7c";
    };
    vlanConfig.Id = 2;
  };

  ###### PHYSICAL NIC -> BRIDGE ######
  systemd.network.networks."10-eno3" = {
    matchConfig.Name = "eno3";
    networkConfig = {
      Bridge = "vmbr4";
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
    networkConfig = {
      # Keep a host management address on VLAN 2 on the bridge master. Putting
      # this on eno3 steals VLAN 2 replies before the bridge can forward them
      # back to nixos-shell VM tap devices.
      VLAN = [ "vlan2" ];
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
