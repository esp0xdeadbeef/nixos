{ config, lib, pkgs, ... }:

# Temporary ALFA USB AP on l-envil, bridging the neon client networks onto the
# cobalt LAN trunk. The Ralink RT3070 (rt2800usb) supports up to 8 AP VAPs, so
# we host two SSIDs here (clients VLAN 30, clients-vpn VLAN 31).
let
  ifname = "wlp0s20f0u2u4u2";
in
{
  sops.secrets = {
    "l-envil-wifi-clients" = {
      sopsFile = ../../../../secrets/l-envil-default-wifi.yaml;
      key = "wifi-clients";
    };
    "l-envil-wifi-clients-vpn" = {
      sopsFile = ../../../../secrets/l-envil-default-wifi.yaml;
      key = "wifi-clients-vpn";
    };
  };

  # The second BSS needs its own virtual interface (VAP); hostapd does not
  # create it for us.
  systemd.services.alfa-vap = {
    description = "Create the secondary ALFA AP VAP";
    wantedBy = [ "hostapd.service" ];
    before = [ "hostapd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.iw}/bin/iw phy phy1 interface add ${ifname}-1 type __ap 2>/dev/null || true
    '';
  };

  services.hostapd = {
    enable = true;
    radios.${ifname} = {
      band = "2g";
      channel = 6;
      countryCode = "NL";
      settings = {
        vlan_tagged_interface = "br-cobalt-lan";
      };
      networks = {
        "${ifname}" = {
          ssid = "neon-clients";
          bssid = "96:fa:21:a0:d7:1b";
          authentication = {
            mode = "wpa3-sae";
            saePasswords = [{ passwordFile = config.sops.secrets."l-envil-wifi-clients".path; }];
          };
          settings = { vlan_id = 30; };
        };
        "${ifname}-1" = {
          ssid = "neon-clients-vpn";
          bssid = "9e:fa:21:a0:d7:1b";
          authentication = {
            mode = "wpa3-sae";
            saePasswords = [{ passwordFile = config.sops.secrets."l-envil-wifi-clients-vpn".path; }];
          };
          settings = { vlan_id = 31; };
        };
      };
    };
  };
}
