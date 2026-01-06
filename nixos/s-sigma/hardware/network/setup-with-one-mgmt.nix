{
  config,
  pkgs,
  lib,
  ...
}:

{
  /**
    ******************************************************************
     GLOBAL NETWORKING
    ******************************************************************
  */
  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network.enable = true;

  # Avoid blocking boot on carrier for bridges
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  /**
    ******************************************************************
     NETDEVS (BRIDGES)
    ******************************************************************
  */
  systemd.network.netdevs = {
    # Management bridge (untagged, non-VLAN-aware)
    "10-vmbr0" = {
      netdevConfig = {
        Name = "vmbr0";
        Kind = "bridge";
      };
    };

    # Full VLAN trunk bridge (Proxmox-style)
    "10-vmbr4" = {
      netdevConfig = {
        Name = "vmbr4";
        Kind = "bridge";
      };
      extraConfig = ''
        [Bridge]
        VLANFiltering=yes
      '';
    };
  };

  /**
    ******************************************************************
     NETWORKS
    ******************************************************************
  */
  systemd.network.networks = {

    /**
      ******************** MGMT (UNTAGGED) *************************
    */
    # Physical NIC for management
    "10-eno4" = {
      matchConfig.Name = "eno4";
      networkConfig = {
        Bridge = "vmbr0";
        DHCP = "no";
        LinkLocalAddressing = "no";
      };
    };

    # Management bridge gets IP (DHCP or static if you prefer)
    "20-vmbr0" = {
      matchConfig.Name = "vmbr0";
      networkConfig = {
        DHCP = "yes";
        ConfigureWithoutCarrier = true;
      };
    };

    /**
      ******************** FULL TRUNK (VLAN 2–4094) ****************
    */
    # Physical trunk NIC
    "40-eno3" = {
      matchConfig.Name = "eno3";
      networkConfig = {
        Bridge = "vmbr4";
        DHCP = "no";
        LinkLocalAddressing = "no";
      };

      # Pure tagged trunk, no native VLAN
      bridgeVLANs = [
        { VLAN = "2-4094"; }
      ];
    };

    # Trunk bridge itself must allow VLANs too
    "41-vmbr4" = {
      matchConfig.Name = "vmbr4";
      networkConfig = {
        DHCP = "no";
        ConfigureWithoutCarrier = true;
      };

      bridgeVLANs = [
        { VLAN = "2-4094"; }
      ];
    };
  };
  systemd.network.networks."99-libvirt-taps" = {
    matchConfig.Name = "vnet*";
    linkConfig = {
      Promiscuous = true;
    };
    extraConfig = ''
      [Bridge]
      HairPin=yes
    '';
  };
}
