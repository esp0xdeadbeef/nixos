{ config, lib, pkgs, ... }:

# l-portal's USB Ethernet is the cobalt clients tenant (VLAN 30,
# 10.2.30.0/24, ULA fd42:dead:beef:c1e::/64) — plain WAN egress, no VPN.
# Its DHCP/SLAAC comes from the cobalt router VM; the only thing l-portal has
# to do locally is source-route the 10.2.30.0/24 traffic out enu1u1 so it does
# not fall back to the WiFi default route.
let
  clientsTable = "3000";
  clientsV4Prefix = "10.2.30.0/24";
  clientsGateway = "10.2.30.1";
in
{
  networking.networkmanager.ensureProfiles = {
    profiles = {
      cobalt-clients = {
        connection = {
          id = "cobalt-clients";
          type = "ethernet";
          interface-name = "enu1u1";
          autoconnect = true;
        };

        ipv4 = {
          method = "auto";
          route-metric = 700;
          route1 = "0.0.0.0/0,${clientsGateway}";
          route1_options = "table=${clientsTable}";
          routing-rule1 = "priority ${clientsTable} from ${clientsV4Prefix} table ${clientsTable}";
        };

        ipv6 = {
          method = "auto";
          route-metric = 700;
        };
      };
    };
  };

  # The auto-created "Wired connection 1" for enu1u1 conflicts with the
  # declarative cobalt-clients profile. Remove it so the declarative profile
  # wins.
  systemd.services.remove-stale-nm-cobalt-clients = {
    description = "Remove auto-created NetworkManager profile for enu1u1";
    wantedBy = [ "multi-user.target" ];
    before = [ "NetworkManager.service" "NetworkManager-ensure-profiles.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      rm -f "/etc/NetworkManager/system-connections/Wired connection 1.nmconnection"
    '';
  };
}
