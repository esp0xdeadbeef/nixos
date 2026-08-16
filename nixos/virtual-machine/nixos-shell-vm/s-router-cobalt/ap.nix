{ config, lib, pkgs, ... }:

# Temporary ALFA USB AP on the cobalt VM host. The USB device is passed
# through via qemu-xhci and appears as wlan0 in the VM's own netns. We drive
# hostapd directly (not via the NixOS hostapd module) so the SSIDs and
# passphrases come from SOPS at runtime and no explicit bssid is required --
# the rt2800usb cannot reliably change its MAC over the passthrough.
#
# Two AP VAPs serve the SSIDs; a third spare VAP (wlan0-scan, station mode)
# is used by an hourly timer to scan the band and trigger a seamless
# 802.11h channel switch (CSA) when a less-congested channel is found.
let
  wifiIf = "wlan0";
  scanIf = "wlan0-scan";
  ctrl = "/run/ap";

  hostapdConf = pkgs.writeShellScript "make-ap-hostapd-conf" ''
    set -euo pipefail
    ssid1=$(cat /run/secrets/wifi-ssid-clients)
    ssid2=$(cat /run/secrets/wifi-ssid-clients-vpn)
    pass1=$(cat /run/secrets/wifi-clients)
    pass2=$(cat /run/secrets/wifi-clients-vpn)
    cat > /run/ap/${wifiIf}.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=${wifiIf}
    driver=nl80211
    ssid=$ssid1
    hw_mode=g
    channel=6
    chanlist=1 6 11
    country_code=NL
    wpa=2
    wpa_key_mgmt=SAE
    sae_pwe=1
    sae_password=$pass1
    bridge=clients
    EOF
    cat > /run/ap/${wifiIf}-1.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=${wifiIf}-1
    driver=nl80211
    ssid=$ssid2
    hw_mode=g
    channel=6
    chanlist=1 6 11
    country_code=NL
    wpa=2
    wpa_key_mgmt=SAE
    sae_pwe=1
    sae_password=$pass2
    bridge=clients-vpn
    EOF
  '';

  chanOptimizer = pkgs.writeShellScript "wifi-chan-optimizer" ''
    set -euo pipefail
    ${pkgs.iproute2}/bin/ip link set ${scanIf} up 2>/dev/null || true
    ${pkgs.iw}/bin/iw dev ${scanIf} scan > /run/ap/scan.txt 2>/dev/null || true

    c1=$(${pkgs.gnugrep}/bin/grep -c "freq: 2412" /run/ap/scan.txt || true)
    c6=$(${pkgs.gnugrep}/bin/grep -c "freq: 2437" /run/ap/scan.txt || true)
    c11=$(${pkgs.gnugrep}/bin/grep -c "freq: 2462" /run/ap/scan.txt || true)

    best=2412
    bestn=$c1
    if [ "$c6" -lt "$bestn" ]; then
      best=2437
      bestn=$c6
    fi
    if [ "$c11" -lt "$bestn" ]; then
      best=2462
      bestn=$c11
    fi

    cur=$(${pkgs.iw}/bin/iw dev ${wifiIf} info | ${pkgs.gnugrep}/bin/grep -oP 'channel \d+ \(\K\d+' || echo 2437)

    if [ "$cur" != "$best" ]; then
      ${pkgs.hostapd}/bin/hostapd_cli -p ${ctrl} -i ${wifiIf} chan_switch 5 "$best"
    fi
  '';
in
{
  systemd.services.ap-vap = {
    description = "Create the ALFA AP and scan VAPs";
    wantedBy = [ "multi-user.target" ];
    before = [ "ap.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for _ in $(seq 1 30); do
        if [ -d /sys/class/net/${wifiIf}-1 ]; then
          break
        fi
        ${pkgs.iw}/bin/iw phy phy0 interface add ${wifiIf}-1 type __ap 2>/dev/null || true
        sleep 1
      done
      for _ in $(seq 1 30); do
        if [ -d /sys/class/net/${scanIf} ]; then
          break
        fi
        ${pkgs.iw}/bin/iw phy phy0 interface add ${scanIf} type station 2>/dev/null || true
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

  systemd.services.wifi-chan-optimizer = {
    description = "Scan and switch the AP to the least-congested 2.4GHz channel";
    after = [ "ap.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = chanOptimizer;
    };
  };

  systemd.timers.wifi-chan-optimizer = {
    description = "Hourly wifi channel re-optimization";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
    };
  };
}
