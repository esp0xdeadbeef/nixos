{ config, lib, pkgs, inputs, relativeRepo, ... }:

# Temporary ALFA USB AP on the cobalt VM host. The USB device is passed
# through via qemu-xhci and appears as wlan0 in the VM's own netns. We drive
# hostapd directly (not via the NixOS hostapd module) so the passphrases come
# from SOPS at runtime and no explicit bssid is required -- the rt2800usb
# cannot reliably change its MAC over the passthrough. SSIDs are derived
# deterministically from a SOPS seed + the vendored wardriving SSID list, so
# no recognizable SSID is ever hardcoded.
#
# At startup a spare station VAP (wlan0-scan) scans the 2.4GHz band and the
# least-congested of channels 1/6/11 is selected for the AP VAPs; no
# channel is hardcoded.
let
  wifiIf = "wlan0";
  unlockIf = "wlan0-2";
  mgmtIf = "wlan0-3";
  scanIf = "wlan0-scan";
  nighthawkIf = "wlan1";
  nighthawkClientsIf = "wlan1-0";
  nighthawkUnlockIf = "wlan1-2";
  nighthawkMgmtIf = "wlan1-3";
  ctrl = "/run/ap";

  ssidList = inputs.wifi-ssids.outPath + "/ssids.txt";
  deriveSsid = pkgs.writeShellScript "derive-ssid" (
    builtins.readFile (relativeRepo.sourcePath "library/01-general/network/wifi-ssid-derive.sh")
  );

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

    seed=$("$YQ" -r '.seed' "$SEC")
    used=/run/ap/used-ssids
    rm -f "$used"
    ssid1=$(${deriveSsid} "$seed" cobalt-clients ${ssidList} "$used")
    ssid2=$(${deriveSsid} "$seed" cobalt-clients-vpn ${ssidList} "$used")
    ssid3=$("$YQ" -r '.cobalt-unlock.ssid' "$SEC")
    ssid4=$(${deriveSsid} "$seed" cobalt-mgmt ${ssidList} "$used")
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

    # Nighthawk AXE3000 (mt7925u) second radio on 5GHz. Same SSIDs and PSKs,
    # so clients roam between the 2.4GHz ALFA and this 5GHz radio.
    cat > /run/ap/${nighthawkIf}.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=${nighthawkIf}
    driver=nl80211
    ssid=$ssid1
    hw_mode=a
    channel=36
    wmm_enabled=1
    country_code=NL
    ieee80211ax=1
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=CCMP
    wpa_passphrase=$pass1
    bridge=clients
    EOF
    cat > /run/ap/${nighthawkIf}-1.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=${nighthawkIf}-1
    driver=nl80211
    ssid=$ssid2
    hw_mode=a
    channel=36
    wmm_enabled=1
    country_code=NL
    ieee80211ax=1
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=CCMP
    wpa_passphrase=$pass2
    bridge=clients-vpn
    EOF
    cat > /run/ap/${nighthawkUnlockIf}.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=${nighthawkUnlockIf}
    driver=nl80211
    ssid=$ssid3
    hw_mode=a
    channel=36
    wmm_enabled=1
    country_code=NL
    ieee80211ax=1
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=CCMP
    wpa_passphrase=$pass3
    bridge=unlock
    EOF
    cat > /run/ap/${nighthawkMgmtIf}.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=${nighthawkMgmtIf}
    driver=nl80211
    ssid=$ssid4
    hw_mode=a
    channel=36
    wmm_enabled=1
    country_code=NL
    ieee80211ax=1
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=CCMP
    wpa_passphrase=$pass4
    bridge=mgmt
    EOF
  '';
in
let
  apVaps = [
    { iface = wifiIf; bridge = "clients"; gw = "10.2.30.1"; }
    { iface = "${wifiIf}-1"; bridge = "clients-vpn"; gw = "10.2.31.1"; }
    { iface = unlockIf; bridge = "unlock"; gw = "10.2.90.1"; }
    { iface = mgmtIf; bridge = "mgmt"; gw = "10.2.10.1"; }
  ];
  mkApUnit = vap: {
    name = "ap-${vap.iface}";
    value = {
      description = "WiFi AP ${vap.iface} on bridge ${vap.bridge}";
      wantedBy = [ "multi-user.target" ];
      after = [ "ap-conf.service" "ap-vap.service" ];
      requires = [ "ap-conf.service" "ap-vap.service" ];
      path = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.iproute2
      ];
      serviceConfig = {
        ExecStart = "${pkgs.hostapd}/bin/hostapd /run/ap/${vap.iface}.conf";
        Restart = "always";
        RestartSec = 3;
      };
      preStart = ''
        for _ in $(seq 1 30); do
          ${pkgs.iproute2}/bin/ip link show ${vap.bridge} 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "state UP" && break
          sleep 1
        done
        ${pkgs.iproute2}/bin/ip link show ${vap.bridge} 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "state UP" || exit 1
        [ -n "$(ls /sys/class/net/${vap.bridge}/brif/ 2>/dev/null)" ] || exit 1
      '';
    };
  };
in
{
  systemd.services = {
    ap-conf = {
      description = "Generate hostapd AP configs";
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.iproute2
        pkgs.iw
        pkgs.yq-go
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = hostapdConf;
        RuntimeDirectory = "ap";
      };
    };

    ap-vap = {
      description = "Create the ALFA AP and scan VAPs";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        alfa_phy=$(cat /sys/class/net/${wifiIf}/phy80211/name 2>/dev/null || echo phy0)
        nh_phy=$(cat /sys/class/net/${nighthawkIf}/phy80211/name 2>/dev/null || echo phy1)
        for _ in $(seq 1 30); do
          if [ -d /sys/class/net/${wifiIf}-1 ]; then
            break
          fi
          ${pkgs.iw}/bin/iw phy "$alfa_phy" interface add ${wifiIf}-1 type __ap 2>/dev/null || true
          sleep 1
        done
        for _ in $(seq 1 30); do
          if [ -d /sys/class/net/${unlockIf} ]; then
            break
          fi
          ${pkgs.iw}/bin/iw phy "$alfa_phy" interface add ${unlockIf} type __ap 2>/dev/null || true
          sleep 1
        done
        for _ in $(seq 1 30); do
          if [ -d /sys/class/net/${mgmtIf} ]; then
            break
          fi
          ${pkgs.iw}/bin/iw phy "$alfa_phy" interface add ${mgmtIf} type __ap 2>/dev/null || true
          sleep 1
        done
        for _ in $(seq 1 30); do
          if [ -d /sys/class/net/${scanIf} ]; then
            break
          fi
          ${pkgs.iw}/bin/iw phy "$alfa_phy" interface add ${scanIf} type station 2>/dev/null || true
          sleep 1
        done
        for _ in $(seq 1 30); do
          if [ -d /sys/class/net/${nighthawkClientsIf} ]; then
            break
          fi
          ${pkgs.iw}/bin/iw phy "$nh_phy" interface add ${nighthawkClientsIf} type __ap 2>/dev/null || true
          sleep 1
        done
        for _ in $(seq 1 30); do
          if [ -d /sys/class/net/${nighthawkIf}-1 ]; then
            break
          fi
          ${pkgs.iw}/bin/iw phy "$nh_phy" interface add ${nighthawkIf}-1 type __ap 2>/dev/null || true
          sleep 1
        done
        for _ in $(seq 1 30); do
          if [ -d /sys/class/net/${nighthawkUnlockIf} ]; then
            break
          fi
          ${pkgs.iw}/bin/iw phy "$nh_phy" interface add ${nighthawkUnlockIf} type __ap 2>/dev/null || true
          sleep 1
        done
        for _ in $(seq 1 30); do
          if [ -d /sys/class/net/${nighthawkMgmtIf} ]; then
            break
          fi
          ${pkgs.iw}/bin/iw phy "$nh_phy" interface add ${nighthawkMgmtIf} type __ap 2>/dev/null || true
          sleep 1
        done
      '';
    };
  } // lib.listToAttrs (map mkApUnit apVaps);
}
