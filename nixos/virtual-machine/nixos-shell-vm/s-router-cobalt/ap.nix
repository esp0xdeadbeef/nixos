{ config, lib, pkgs, ... }:

# Temporary ALFA USB AP on the cobalt VM host. The USB device is passed
# through via qemu-xhci and appears as wlan0 in the VM's own netns. We drive
# hostapd directly (not via the NixOS hostapd module) so the SSIDs and
# passphrases come from SOPS at runtime and no explicit bssid is required --
# the rt2800usb cannot reliably change its MAC over the passthrough.
#
# At startup a spare station VAP (wlan0-scan) scans the 2.4GHz band and the
# least-congested of channels 1/6/11 is selected for the AP VAPs; no
# channel is hardcoded.
let
  wifiIf = "wlan0";
  unlockIf = "wlan0-2";
  mgmtIf = "wlan0-3";
  scanIf = "wlan0-scan";
  ctrl = "/run/ap";

  hostapdConf = pkgs.writeShellScript "make-ap-hostapd-conf" ''
    set -euo pipefail

    # Scan and pick the least-congested 2.4GHz channel (1/6/11).
    ${pkgs.iproute2}/bin/ip link set ${scanIf} up 2>/dev/null || true
    sleep 2
    ${pkgs.iw}/bin/iw dev ${scanIf} scan > /run/ap/scan.txt 2>/dev/null || true
    ${pkgs.iproute2}/bin/ip link set ${scanIf} down 2>/dev/null || true

    c1=$(${pkgs.gnugrep}/bin/grep -c "freq: 2412" /run/ap/scan.txt || true)
    c6=$(${pkgs.gnugrep}/bin/grep -c "freq: 2437" /run/ap/scan.txt || true)
    c11=$(${pkgs.gnugrep}/bin/grep -c "freq: 2462" /run/ap/scan.txt || true)

    bestfreq=2412
    bestn=$c1
    if [ "$c6" -lt "$bestn" ]; then
      bestfreq=2437
      bestn=$c6
    fi
    if [ "$c11" -lt "$bestn" ]; then
      bestfreq=2462
      bestn=$c11
    fi

    case "$bestfreq" in
      2412) ch=1 ;;
      2437) ch=6 ;;
      2462) ch=11 ;;
      *) ch=6 ;;
    esac

    YQ=${pkgs.yq-go}/bin/yq
    SEC=/run/secrets/cobalt-wifi

    ssid1=$("$YQ" -r '.cobalt-clients.ssid' "$SEC")
    ssid2=$("$YQ" -r '.cobalt-clients-vpn.ssid' "$SEC")
    ssid3=$("$YQ" -r '.cobalt-unlock.ssid' "$SEC")
    ssid4=$("$YQ" -r '.cobalt-mgmt.ssid' "$SEC")
    pass1=$("$YQ" -r '.cobalt-clients.psk' "$SEC")
    pass2=$("$YQ" -r '.cobalt-clients-vpn.psk' "$SEC")
    pass3=$("$YQ" -r '.cobalt-unlock.psk' "$SEC")
    pass4=$("$YQ" -r '.cobalt-mgmt.psk' "$SEC")

    cat > /run/ap/${wifiIf}.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=${wifiIf}
    driver=nl80211
    ssid=$ssid1
    hw_mode=g
    channel=$ch
    wmm_enabled=1
    country_code=NL
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=CCMP
    wpa_passphrase=$pass1
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
    channel=$ch
    wmm_enabled=1
    country_code=NL
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=CCMP
    wpa_passphrase=$pass2
    bridge=clients-vpn
    EOF
    cat > /run/ap/${unlockIf}.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=${unlockIf}
    driver=nl80211
    ssid=$ssid3
    hw_mode=g
    channel=$ch
    wmm_enabled=1
    country_code=NL
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=CCMP
    wpa_passphrase=$pass3
    bridge=unlock
    EOF
    cat > /run/ap/${mgmtIf}.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=${mgmtIf}
    driver=nl80211
    ssid=$ssid4
    hw_mode=g
    channel=$ch
    wmm_enabled=1
    country_code=NL
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=CCMP
    wpa_passphrase=$pass4
    bridge=mgmt
    EOF
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
        if [ -d /sys/class/net/${unlockIf} ]; then
          break
        fi
        ${pkgs.iw}/bin/iw phy phy0 interface add ${unlockIf} type __ap 2>/dev/null || true
        sleep 1
      done
      for _ in $(seq 1 30); do
        if [ -d /sys/class/net/${mgmtIf} ]; then
          break
        fi
        ${pkgs.iw}/bin/iw phy phy0 interface add ${mgmtIf} type __ap 2>/dev/null || true
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
      ExecStart = "${pkgs.hostapd}/bin/hostapd /run/ap/${wifiIf}.conf /run/ap/${wifiIf}-1.conf /run/ap/${unlockIf}.conf /run/ap/${mgmtIf}.conf";
      Restart = "always";
      RuntimeDirectory = "ap";
    };
  };
}
