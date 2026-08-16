{ config, lib, pkgs, ... }:

# Temporary ALFA USB AP on the cobalt VM host. The USB device is passed
# through via qemu-xhci and appears as wlan0 in the VM's own netns. Each
# SSID bridges onto the existing container bridge (clients VLAN 30,
# clients-vpn VLAN 31).
let
  wifiIf = "wlan0";
in
{
  systemd.services.ap-vap = {
    description = "Create the secondary ALFA AP VAP";
    wantedBy = [ "hostapd.service" ];
    before = [ "hostapd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.iw}/bin/iw phy phy0 interface add ${wifiIf}-1 type __ap 2>/dev/null || true
    '';
  };

  services.hostapd = {
    enable = true;
    radios.${wifiIf} = {
      band = "2g";
      channel = 6;
      countryCode = "NL";
      networks = {
        "${wifiIf}" = {
          ssid = "cobalt-clients";
          bssid = "02:00:00:00:00:01";
          authentication = {
            mode = "wpa3-sae";
            saePasswords = [{ passwordFile = config.sops.secrets."cobalt-wifi-clients".path; }];
          };
          settings = { bridge = "clients"; };
        };
        "${wifiIf}-1" = {
          ssid = "cobalt-clients-vpn";
          bssid = "02:00:00:00:00:02";
          authentication = {
            mode = "wpa3-sae";
            saePasswords = [{ passwordFile = config.sops.secrets."cobalt-wifi-clients-vpn".path; }];
          };
          settings = { bridge = "clients-vpn"; };
        };
      };
    };
  };
}
