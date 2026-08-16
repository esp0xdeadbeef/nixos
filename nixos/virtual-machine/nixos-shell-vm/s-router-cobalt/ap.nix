{ config, lib, pkgs, ... }:

# Temporary ALFA USB AP on the cobalt VM host. The USB device is passed
# through via qemu-xhci and appears as wlan0 in the VM's own netns. The
# rt2800usb cannot reliably change its MAC over the passthrough, so each
# SSID is its own single-BSS radio (no explicit bssid). Each SSID bridges
# onto the existing container bridge (clients VLAN 30, clients-vpn VLAN 31).
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

  # The secondary VAP (wlan0-1) is created at runtime by ap-vap, so systemd
  # cannot track it as a device unit. Drop the device binding and order the
  # start after the VAP exists.
  systemd.services.hostapd.bindsTo = lib.mkForce [ ];
  systemd.services.hostapd.after = lib.mkForce [ "ap-vap.service" ];

  services.hostapd = {
    enable = true;
    radios = {
      "${wifiIf}" = {
        band = "2g";
        channel = 6;
        countryCode = "NL";
        networks."${wifiIf}" = {
          ssid = "cobalt-clients";
          authentication = {
            mode = "wpa3-sae";
            saePasswords = [{ passwordFile = config.sops.secrets."cobalt-wifi-clients".path; }];
          };
          settings = { bridge = "clients"; };
        };
      };
      "${wifiIf}-1" = {
        band = "2g";
        channel = 6;
        countryCode = "NL";
        networks."${wifiIf}-1" = {
          ssid = "cobalt-clients-vpn";
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
