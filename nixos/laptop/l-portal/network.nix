{ config, lib, pkgs, ... }:

# l-portal's USB Ethernet is the cobalt clients-vpn tenant (VLAN 31,
# 10.2.31.0/24, ULA fd42:dead:beef:c1f::/64) — egresses via the AirVPN onyx
# tunnel. Its DHCP/SLAAC comes from the cobalt router VM; the only thing
# l-portal has to do locally is source-route the 10.2.31.0/24 traffic out
# enu1u1 so it does not fall back to the WiFi default route.
let
  clientsTable = "3100";
  clientsV4Prefix = "10.2.31.0/24";
  clientsGateway = "10.2.31.1";
in
{
  networking.networkmanager.ensureProfiles = {
    profiles = {
      cobalt-clients-vpn = {
        connection = {
          id = "cobalt-clients-vpn";
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

  # The auto-created "Wired connection 1" for enu1u1 and the previous
  # cobalt-clients profile conflict with the declarative profile. Remove them
  # so the declarative profile wins.
  systemd.services.remove-stale-nm-cobalt-clients-vpn = {
    description = "Remove stale NetworkManager profiles for enu1u1";
    wantedBy = [ "multi-user.target" ];
    before = [ "NetworkManager.service" "NetworkManager-ensure-profiles.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      rm -f "/etc/NetworkManager/system-connections/Wired connection 1.nmconnection"
      rm -f "/run/NetworkManager/system-connections/cobalt-clients.nmconnection"
    '';
  };
}
