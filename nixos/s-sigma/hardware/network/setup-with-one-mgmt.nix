{
  config,
  pkgs,
  lib,
  ...
}:

{
  /**
    ******************************************************************
     GLOBAL
    ******************************************************************
  */
  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network.enable = true;
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  /**
    ******************************************************************
     NETDEVS (BRIDGES)
    ******************************************************************
  */
  systemd.network.netdevs = {
    # MANAGEMENT — DO NOT TOUCH
    "10-vmbr0" = {
      netdevConfig = {
        Name = "vmbr0";
        Kind = "bridge";
      };
    };

    # ISP — FULL TRUNK
    "10-vmbr1" = {
      netdevConfig = {
        Name = "vmbr1";
        Kind = "bridge";
      };
      extraConfig = ''
        [Bridge]
        VLANFiltering=yes
      '';
    };

    # LAN / TRUNK — FULL TRUNK
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
      ****************** MGMT (UNTOUCHED) ***************************
    */
    "10-eno4" = {
      matchConfig.Name = "eno4";
      networkConfig = {
        Bridge = "vmbr0";
        DHCP = "no";
        LinkLocalAddressing = "no";
      };
    };

    "20-vmbr0" = {
      matchConfig.Name = "vmbr0";

      networkConfig = {
        DHCP = "ipv4";
        ConfigureWithoutCarrier = true;
        LinkLocalAddressing = "no";
      };

      dhcpV4Config = {
        ClientIdentifier = "mac";
        SendRelease = false;
        MaxAttempts = 0;
        UseRoutes = true;
        UseGateway = true;
      };

      extraConfig = ''
        [DHCPv4]
        KeepConfiguration=yes
      '';
    };

    /**
      ****************** ISP — FULL TRUNK ***************************
    */
    "30-enp132s0f1" = {
      matchConfig.Name = "enp132s0f1";
      networkConfig = {
        Bridge = "vmbr1";
        DHCP = "no";
        LinkLocalAddressing = "no";
      };

      # FULL TRUNK
      bridgeVLANs = [
        { VLAN = "2-4094"; }
      ];
    };

    "31-vmbr1" = {
      matchConfig.Name = "vmbr1";
      networkConfig = {
        DHCP = "no";
        ConfigureWithoutCarrier = true;
      };

      # FULL TRUNK
      bridgeVLANs = [
        { VLAN = "2-4094"; }
      ];
    };

    /**
      ****************** LAN / TRUNK — FULL TRUNK *******************
    */
    "40-eno3" = {
      matchConfig.Name = "eno3";
      networkConfig = {
        Bridge = "vmbr4";
        DHCP = "no";
        LinkLocalAddressing = "no";
      };

      # FULL TRUNK
      bridgeVLANs = [
        { VLAN = "2-4094"; }
      ];
    };

    "41-vmbr4" = {
      matchConfig.Name = "vmbr4";
      networkConfig = {
        DHCP = "no";
        ConfigureWithoutCarrier = true;
      };

      # FULL TRUNK
      bridgeVLANs = [
        { VLAN = "2-4094"; }
      ];
    };

    /**
      ****************** LIBVIRT TAPS ******************************
    */
    #"99-libvirt-taps" = {
    #  matchConfig.Name = "vnet*";
    #  linkConfig = {
    #    Promiscuous = true;
    #  };
    #  extraConfig = ''
    #    [Bridge]
    #    HairPin=yes
    #  '';
    #};
    #"99-libvirt-taps" = {
    #  matchConfig.Name = "vnet*";

    #  linkConfig = {
    #    Promiscuous = true;
    #  };

    #  # Allow trunk VLANs to pass on tap ports
    #  bridgeVLANs = [
    #    { VLAN = "2-4094"; }
    #  ];

    #  extraConfig = ''
    #    [Bridge]
    #    HairPin=yes
    #  '';
    #};

  };
  environment.etc."qemu/bridge.conf".text = ''
    allow vmbr0
    allow vmbr1
    allow vmbr4
  '';

}
