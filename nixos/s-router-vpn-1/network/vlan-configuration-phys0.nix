{
  config,
  pkgs,
  lib,
  ...
}:

{
  networking.useNetworkd = true;

  # Disable networkd-wait-online
  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;

  systemd.network = {
    enable = true;

    # Rename ens19 to phys0
    links."10-phys0" = {
      matchConfig.PermanentMACAddress = "bc:24:11:28:1f:b6";
      linkConfig.Name = "phys0";
    };
    # Attach only the DHCP VLANs to phys0
    networks."10-phys0" = {
      matchConfig.Name = "phys0";
      networkConfig.VLAN = [
        "vlan-lan"
        "vlan-test"
        "vlan-natted-internal"
      ];
    };

    # VLAN for LAN (ID: 4) with DHCP
    netdevs."10-vlan-lan" = {
      netdevConfig = {
        Kind = "vlan";
        Name = "vlan-lan";
      };
      vlanConfig.Id = 4;
    };
    networks."10-vlan-lan" = {
      matchConfig.Name = "vlan-lan";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      dhcpConfig.RouteMetric = 150;
    };

    # VLAN for Test (ID: 5) with DHCP
    netdevs."20-vlan-test" = {
      netdevConfig = {
        Kind = "vlan";
        Name = "vlan-test";
      };
      vlanConfig.Id = 5;
    };
    networks."20-vlan-test" = {
      matchConfig.Name = "vlan-test";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      dhcpConfig.RouteMetric = 150;
    };

    # VLAN for vlan-natted-internal (ID: 10) with static IP and a high default route metric
    netdevs."30-vlan-natted-internal" = {
      netdevConfig = {
        Kind = "vlan";
        Name = "vlan-natted-internal";
      };
      vlanConfig.Id = 10;
    };
    networks."30-vlan-natted-internal" = {
      matchConfig.Name = "vlan-natted-internal";
      addresses = [
        { Address = "192.168.80.20/24"; }
        { Address = "fd80:dead:beef::1/64"; }
      ];
      networkConfig = {
        DHCP         = "no";
        IPv6AcceptRA = false;
        DNS          = "192.168.80.1";
        # Remove Gateway here to avoid automatic default route creation.
      };
      routes = [
        {
          Destination = "0.0.0.0/0";
          Gateway     = "192.168.80.1";
          Metric      = 1024;  # This sets the default route with a high metric.
        }
      ];
    };


  };
}
