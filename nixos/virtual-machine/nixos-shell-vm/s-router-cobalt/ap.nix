{ config, lib, pkgs, ... }:

# Temporary ALFA USB AP on the cobalt VM host. The USB device is passed
# through via qemu-xhci and appears as wlan0 in the VM's own netns. We drive
# hostapd directly (not via the NixOS hostapd module) so that the SSIDs and
# passphrases come from SOPS at runtime and no explicit bssid is required --
# the rt2800usb cannot reliably change its MAC over the passthrough.
let
  wifiIf = "wlan0";

  hostapdConf = pkgs.writeShellScript "make-ap-hostapd-conf" ''
    set -euo pipefail
    ssid1=$(cat /run/secrets/wifi-ssid-clients)
    ssid2=$(cat /run/secrets/wifi-ssid-clients-vpn)
    pass1=$(cat /run/secrets/wifi-clients)
    pass2=$(cat /run/secrets/wifi-clients-vpn)
    cat > /run/ap/${wifiIf}.conf <<EOF
    interface=${wifiIf}
    driver=nl80211
    ssid=$ssid1
    hw_mode=g
    channel=6
    country_code=NL
    wpa=2
    wpa_key_mgmt=SAE
    sae_pwe=2
    wpa_passphrase=$pass1
    bridge=clients
    EOF
    cat > /run/ap/${wifiIf}-1.conf <<EOF
    interface=${wifiIf}-1
    driver=nl80211
    ssid=$ssid2
    hw_mode=g
    channel=6
    country_code=NL
    wpa=2
    wpa_key_mgmt=SAE
    sae_pwe=2
    wpa_passphrase=$pass2
    bridge=clients-vpn
    EOF
  '';
in
{
  systemd.services.ap-vap = {
    description = "Create the secondary ALFA AP VAP";
    wantedBy = [ "multi-user.target" ];
    before = [ "ap.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for _ in $(seq 1 30); do
        if [ -d /sys/class/net/${wifiIf}-1 ]; then
          exit 0
        fi
        ${pkgs.iw}/bin/iw phy phy0 interface add ${wifiIf}-1 type __ap 2>/dev/null || true
        sleep 1
      done
    '';
  };

  systemd.services.ap = {
    description = "ALFA USB access point";
    wantedBy = [ "multi-user.target" ];
    after = [ "ap-vap.service" ];
    requires = [ "ap-vap.service" ];
    serviceConfig = {
      ExecStartPre = hostapdConf;
      ExecStart = "${pkgs.hostapd}/bin/hostapd /run/ap/${wifiIf}.conf /run/ap/${wifiIf}-1.conf";
      Restart = "always";
      RuntimeDirectory = "ap";
    };
  };
}
