{ config, pkgs, lib, ... }:

{
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.networkmanager.enable = lib.mkForce false;

  # Disable wait-online (good for VMs)
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  systemd.network = {
    enable = true;

    # VLAN interface eth0.2
    netdevs = {
      "10-eth0-vlan2" = {
        netdevConfig = {
          Name = "eth0.2";
          Kind = "vlan";
        };
        vlanConfig.Id = 2;
      };
    };

    networks = {
      # Parent interface
      "10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          VLAN = "eth0.2";
        };
      };

      # Management interface (VLAN 2) via DHCP
      "20-eth0.2" = {
        matchConfig.Name = "eth0.2";
        networkConfig = {
          DHCP = "ipv4";
          LinkLocalAddressing = "no";
        };
      };
    };
  };
}

