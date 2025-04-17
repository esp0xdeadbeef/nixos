{
  config,
  pkgs,
  lib,
  ...
}:

{

  networking.useNetworkd = true;
  networking.networkmanager.enable = true;

  # Optional but helpful: force NM to manage ens18
  networking.networkmanager.unmanaged = [ "phys0" ];

  # Disable systemd-networkd-wait-online
  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;


  systemd.network = {
    enable = true;

    # Rename ens19 to phys0 by MAC
    links."10-phys0" = {
      matchConfig.PermanentMACAddress = "bc:24:11:28:1f:b6";
      linkConfig.Name = "phys0";
    };

    # Define VLANs 2 and 3
    netdevs."10-vlan-lan" = {
      netdevConfig = {
        Kind = "vlan";
        Name = "vlan-lan";
      };
      vlanConfig.Id = 2;
    };

    netdevs."10-vlan-iot" = {
      netdevConfig = {
        Kind = "vlan";
        Name = "vlan-iot";
      };
      vlanConfig.Id = 3;
    };

    # Define bridges for LAN and IOT
    netdevs."10-bridge-lan".netdevConfig = {
      Kind = "bridge";
      Name = "br-lan";
    };

    netdevs."10-bridge-iot".netdevConfig = {
      Kind = "bridge";
      Name = "br-iot";
    };

    # Assign VLANs to physical interface (phys0 = ens19)
    networks."20-vlan-to-phys" = {
      matchConfig.Name = "phys0";
      networkConfig.VLAN = [
        "vlan-lan"
        "vlan-iot"
      ];
    };

    # Connect VLAN interfaces to bridges
    networks."20-vlan-br-lan" = {
      matchConfig.Name = "vlan-lan";
      networkConfig.Bridge = "br-lan";
    };

    # networks."20-vlan-br-iot" = {
    #   matchConfig.Name = "vlan-iot";
    #   networkConfig.Bridge = "br-iot";
    # };

    # Configure br-lan with static IP (optional)
    networks."30-br-lan" = {
      matchConfig.Name = "br-lan";
      # addresses = [
      #   {
      #     addressConfig.Address = "192.168.80.20/24";
      #   }
      # ];
      # networkConfig = {
      #   Gateway = "192.168.80.1";
      #   DNS = "192.168.80.1";
      # };
    };

    # Configure br-iot to just be up (no IP)
    networks."30-br-iot".matchConfig.Name = "br-iot";

    # Optional: auto-bridge matching VM interfaces (if using VMs)
    networks."40-vm-br-lan" = {
      matchConfig.Name = "vm-lan-*";
      networkConfig.Bridge = "br-lan";
    };

    networks."40-vm-br-iot" = {
      matchConfig.Name = "vm-iot-*";
      networkConfig.Bridge = "br-iot";
    };
  };
}
