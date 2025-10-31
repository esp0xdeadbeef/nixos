{
  config,
  lib,
  pkgs,
  ...
}:

let
  lan = "ens21.1337";
in
{
  networking.useNetworkd = true;
  networking.enableIPv6 = true;
  networking.firewall.enable = true;
  systemd.network.enable = true;

  # LAN VLAN ID 2
  systemd.network.netdevs."10-${lan}" = {
    netdevConfig.Name = lan;
    netdevConfig.Kind = "vlan";
    vlanConfig.Id = 2;
  };

  systemd.network.networks."20-${lan}" = {
    matchConfig.Name = lan;

    address = [ "192.168.50.1/24" ];

    networkConfig = {
      DHCPPrefixDelegation = true;
      IPv6SendRA = true;
      IPv6AcceptRA = false;
    };

    ipv6SendRAConfig = {
      EmitDNS = true;
    };
  };

  # ✅ Kea DHCPv4 replacement
  services.kea.dhcp4 = {
    enable = true;

    settings = {
      interfaces-config = {
        interfaces = [ lan ];
      };

      lease-database = {
        type = "memfile";
        persist = true;
        name = "/var/lib/kea/dhcp4.leases";
      };

      subnet4 = [
        {
          subnet = "192.168.50.0/24";
          pools = [ { pool = "192.168.50.100 - 192.168.50.200"; } ];
          option-data = [
            {
              name = "routers";
              data = "192.168.50.1";
            }
            {
              name = "domain-name-servers";
              data = "192.168.50.1";
            }
          ];
        }
      ];
    };
  };

  # NAT (LAN → PPPoE)
  networking.nat = {
    enable = true;
    externalInterface = "ppp0";
    internalInterfaces = [ lan ];
  };

  networking.firewall.interfaces.${lan}.allowedUDPPorts = [
    53
    67
  ];
}
