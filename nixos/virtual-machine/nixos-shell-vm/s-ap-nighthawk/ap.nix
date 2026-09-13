{ config, lib, pkgs, inputs, relativeRepo, ... }:

# Nighthawk AXE3000 (mt7925u, 0846:9072) AP on a dedicated VM. The device is
# passed through via qemu-xhci and appears as wlan0 (phy0) in the VM's own
# netns. It owns the 5GHz clients / clients-vpn SSIDs and bridges them into
# VLAN 30 (clients) and VLAN 31 (clients-vpn) on the cobalt LAN trunk.
#
# WPA3-Personal (SAE) everywhere. SSIDs are derived deterministically from the
# SOPS seed so they match the cobalt router's derivation for the same planes.
#
# Channel: fixed to 36 @ 80MHz. DFS (52-64/100-140) is unavailable on the
# mt7925u (no RDD in firmware), and the NL regulatory domain caps 5.8GHz
# (149-165) at only 25 mW / 13 dBm EIRP vs 200 mW / 23 dBm on 36, so 36 is the
# strongest legal 5GHz option this radio can transmit.
#
# 2.4GHz is deliberately NOT enabled here: running concurrent 2.4+5 GHz BSSes
# on this single-radio part makes the firmware reset in a loop
# ("mt7925u ... Message 00020002 timeout"), which kills beacons and
# associations on BOTH bands. 2.4GHz coverage is provided by the separate ALFA
# (rt2800usb) AP instead.
let
  wifiIf = "wlan0";
  ctrl = "/run/ap";

  ssidList = inputs.wifi-ssids.outPath + "/ssids.txt";
  deriveSsid = pkgs.writeShellScript "derive-ssid" (
    builtins.readFile (relativeRepo.sourcePath "library/01-general/network/wifi-ssid-derive.sh")
  );

  # (iface, network, bridge). Channel/width are fixed (see the header comment).
  vaps = [
    { iface = "wlan0-0"; net = "cobalt-clients"; bridge = "ap-clients"; }
    { iface = "wlan0-1"; net = "cobalt-clients-vpn"; bridge = "ap-clients-vpn"; }
  ];

  hostapdConf = pkgs.writeShellScript "make-ap-hostapd-conf" ''
        set -euo pipefail
        YQ=${pkgs.yq-go}/bin/yq
        SEC=/run/secrets/cobalt-wifi
        mkdir -p ${ctrl}

        # ---- deterministic SSIDs + passphrases ----
        seed=$("$YQ" -r '.seed' "$SEC")
        used=/run/ap/used-ssids
        rm -f "$used"
        ssid_clients=$(${deriveSsid} "$seed" cobalt-clients ${ssidList} "$used")
        ssid_cvpn=$(${deriveSsid} "$seed" cobalt-clients-vpn ${ssidList} "$used")
        pass_clients=$("$YQ" -r '.cobalt-clients.psk' "$SEC")
        pass_cvpn=$("$YQ" -r '.cobalt-clients-vpn.psk' "$SEC")

        # ---- generate one config per SSID (channel 36 @ 80MHz) ----
        for spec in "wlan0-0:cobalt-clients:ap-clients" "wlan0-1:cobalt-clients-vpn:ap-clients-vpn"; do
          iface="''${spec%%:*}"
          rest="''${spec#*:}"
          net="''${rest%%:*}"
          bridge="''${rest#*:}"
          case "$net" in
            cobalt-clients) ssid="$ssid_clients"; pass="$pass_clients" ;;
            cobalt-clients-vpn) ssid="$ssid_cvpn"; pass="$pass_cvpn" ;;
          esac
          cat > ${ctrl}/$iface.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=$iface
    driver=nl80211
    ssid=$ssid
    hw_mode=a
    channel=36
    wmm_enabled=1
    country_code=NL
    ieee80211n=1
    ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40]
    ieee80211ac=1
    vht_oper_chwidth=1
    vht_oper_centr_freq_seg0_idx=42
    vht_capab=[SHORT-GI-80][SHORT-GI-160][MAX-MPDU-11454]
    ieee80211ax=1
    he_oper_chwidth=1
    he_oper_centr_freq_seg0_idx=42
    wpa=2
    wpa_key_mgmt=SAE
    wpa_pairwise=CCMP
    wpa_passphrase=$pass
    ieee80211w=2
    bridge=$bridge
    EOF
        done
  '';

  mkApUnit =
    v: {
      name = "ap-${v.iface}";
      value = {
        description = "Nighthawk AP ${v.iface} on bridge ${v.bridge}";
        wantedBy = [ "multi-user.target" ];
        after = [ "ap-conf.service" "ap-vap.service" ];
        requires = [ "ap-conf.service" "ap-vap.service" ];
        path = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.iproute2
        ];
        serviceConfig = {
          ExecStart = "${pkgs.hostapd}/bin/hostapd ${ctrl}/${v.iface}.conf";
          Restart = "always";
          RestartSec = 3;
        };
        preStart = ''
          for _ in $(seq 1 30); do
            ${pkgs.iproute2}/bin/ip link show ${v.bridge} 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "state UP" && break
            sleep 1
          done
          ${pkgs.iproute2}/bin/ip link show ${v.bridge} 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "state UP" || exit 1
        '';
      };
    };
in
{
  systemd.services = {
    ap-conf = {
      description = "Generate Nighthawk hostapd configs";
      wantedBy = [ "multi-user.target" ];
      after = [ "ap-vap.service" "sops-install-secrets.service" ];
      requires = [ "ap-vap.service" ];
      path = [
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
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
      description = "Create the Nighthawk AP VAPs";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        phy=$(cat /sys/class/net/${wifiIf}/phy80211/name 2>/dev/null || echo phy0)
        ${lib.concatMapStringsSep "\n" (v: ''
          for _ in $(seq 1 30); do
            if [ -d /sys/class/net/${v.iface} ]; then
              break
            fi
            ${pkgs.iw}/bin/iw phy "$phy" interface add ${v.iface} type __ap 2>/dev/null || true
            sleep 1
          done
        '') vaps}
      '';
    };
  } // lib.listToAttrs (map mkApUnit vaps);
}
