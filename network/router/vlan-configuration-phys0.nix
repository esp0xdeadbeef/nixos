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

    # VLAN 2 - LAN
    netdevs."10-vlan-lan" = {
      netdevConfig = {
        Kind = "vlan";
        Name = "vlan-lan";
      };
      vlanConfig.Id = 3;
    };

    # VLAN 3 - IoT
    netdevs."10-vlan-forwarded-vpn" = {
      netdevConfig = {
        Kind = "vlan";
        Name = "vlan-forwarded-vpn";
      };
      vlanConfig.Id = 4;
    };

    # Attach VLANs to phys0
    networks."10-phys0" = {
      matchConfig.Name = "phys0";
      networkConfig.VLAN = [ "vlan-lan" "vlan-forwarded-vpn" ];
    };

    # DHCP for vlan-lan (no default route)
    networks."20-vlan-lan" = {
      matchConfig.Name = "vlan-lan";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      dhcpConfig.RouteMetric = 150;
      dhcpV4Config.UseGateway = false;
    };

    # DHCP for vlan-iot (no default route)
    networks."20-vlan-forwarded-vpn" = {
      matchConfig.Name = "vlan-forwarded-vpn";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      dhcpConfig.RouteMetric = 150;
      dhcpV4Config.UseGateway = false;
    };
  };
}
