{ config, lib, pkgs, inputs, relativeRepo, ... }:

# Dedicated 2.4GHz AP VM for the ALFA AWUS036NHA (rt2800usb, 148f:3070).
# The USB device is passed through via qemu-xhci and appears as wlan0 (phy0).
# It serves the unlock (VLAN 90) and mgmt (VLAN 10) SSIDs and bridges them
# onto the cobalt LAN trunk, exactly like the Nighthawk AP VM does for the
# 5GHz clients planes. Keeping this off s-router-cobalt means router rebuilds
# no longer bounce the 2.4GHz radios.
#
# We drive hostapd directly so the passphrases come from SOPS at runtime and
# no explicit bssid is required (the rt2800usb cannot reliably change its MAC
# over the passthrough). SSIDs are derived deterministically from the SOPS
# seed + the vendored wardriving SSID list.
let
  wifiIf = "wlan0";
  scanIf = "wlan0-scan";
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
    ssid_unlock=$("$YQ" -r '.cobalt-unlock.ssid' "$SEC")
    ssid_mgmt=$(${deriveSsid} "$seed" cobalt-mgmt ${ssidList} "$used")
    pass_unlock=$("$YQ" -r '.cobalt-unlock.psk' "$SEC")
    pass_mgmt=$("$YQ" -r '.cobalt-mgmt.psk' "$SEC")

    cat > /run/ap/${wifiIf}.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=${wifiIf}
    driver=nl80211
    ssid=$ssid_unlock
    hw_mode=g
    channel=$ch
    wmm_enabled=1
    country_code=NL
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=CCMP
    wpa_passphrase=$pass_unlock
    bridge=ap-unlock
    EOF
    cat > /run/ap/${wifiIf}-1.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=${wifiIf}-1
    driver=nl80211
    ssid=$ssid_mgmt
    hw_mode=g
    channel=$ch
    wmm_enabled=1
    country_code=NL
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=CCMP
    wpa_passphrase=$pass_mgmt
    bridge=ap-mgmt
    EOF
  '';

  apVaps = [
    { iface = wifiIf; bridge = "ap-unlock"; }
    { iface = "${wifiIf}-1"; bridge = "ap-mgmt"; }
  ];
  mkApUnit =
    vap: {
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
        '';
      };
    };
in
{
  systemd.services = {
    ap-conf = {
      description = "Generate hostapd AP configs";
      wantedBy = [ "multi-user.target" ];
      after = [ "ap-vap.service" "sops-install-secrets.service" ];
      requires = [ "ap-vap.service" ];
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
        phy=$(cat /sys/class/net/${wifiIf}/phy80211/name 2>/dev/null || echo phy0)
        for _ in $(seq 1 30); do
          if [ -d /sys/class/net/${wifiIf}-1 ]; then
            break
          fi
          ${pkgs.iw}/bin/iw phy "$phy" interface add ${wifiIf}-1 type __ap 2>/dev/null || true
          sleep 1
        done
        for _ in $(seq 1 30); do
          if [ -d /sys/class/net/${scanIf} ]; then
            break
          fi
          ${pkgs.iw}/bin/iw phy "$phy" interface add ${scanIf} type station 2>/dev/null || true
          sleep 1
        done
      '';
    };
  } // lib.listToAttrs (map mkApUnit apVaps);
}
