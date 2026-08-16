{ config, lib, pkgs, ... }:

# l-portal's USB Ethernet is the cobalt clients-vpn tenant (VLAN 31,
# 10.2.31.0/24, ULA fd42:dead:beef:c1f::/64). Its DHCP/SLAAC comes from the
# cobalt router VM; the only thing l-portal has to do locally is source-route
# the 10.2.31.0/24 traffic out enu1u1 so it does not fall back to the WiFi
# default route.
let
  vpnTable = "3100";
  vpnV4Prefix = "10.2.31.0/24";
  vpnGateway = "10.2.31.1";
in
{
  networking.networkmanager.ensureProfiles = {
    profiles = {
      cobalt-vpn = {
        connection = {
          id = "cobalt-vpn";
          type = "ethernet";
          interface-name = "enu1u1";
          autoconnect = true;
        };

        ipv4 = {
          method = "auto";
          route-metric = 700;
          route1 = "0.0.0.0/0,${vpnGateway}";
          route1_options = "table=${vpnTable}";
          routing-rule1 = "priority ${vpnTable} from ${vpnV4Prefix} table ${vpnTable}";
        };

        ipv6 = {
          method = "auto";
          route-metric = 700;
        };
      };
    };
  };

  # The auto-created "Wired connection 1" for enu1u1 conflicts with the
  # declarative cobalt-vpn profile. Remove it so the declarative profile wins.
  systemd.services.remove-stale-nm-cobalt-vpn = {
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
