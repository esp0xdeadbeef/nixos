{ config, lib, pkgs, inputs, relativeRepo, ... }:

# Nighthawk AXE3000 (mt7925u, 0846:9072) AP on a dedicated VM. The device is
# passed through via qemu-xhci and appears as wlan0 (phy0) in the VM's own
# netns. It owns the 5GHz clients / clients-vpn SSIDs and bridges them into
# VLAN 30 (clients) and VLAN 31 (clients-vpn) on the cobalt LAN trunk.
#
# WPA3-Personal (SAE) everywhere. SSIDs are derived deterministically from the
# SOPS seed so they match the cobalt router's derivation for the same planes.
#
# Channel selection: a spare station VAP scans 5GHz at startup and picks the
# least-congested plan, preferring 160MHz (channel 36, DFS) for throughput and
# falling back to 80MHz on channel 36 or 149 so we do not sit on a busy channel.
let
  wifiIf = "wlan0";
  scanIf = "wlan0-scan";
  ctrl = "/run/ap";

  ssidList = inputs.wifi-ssids.outPath + "/ssids.txt";
  deriveSsid = pkgs.writeShellScript "derive-ssid" (
    builtins.readFile (relativeRepo.sourcePath "library/01-general/network/wifi-ssid-derive.sh")
  );

  # 160MHz on channel 36 needs DFS radar detection on 52-64, which the
  # mt7925u client firmware/driver does not implement (start_dfs_cac fails),
  # so 80MHz is the ceiling. Keep the knob so a DFS-capable radio could opt in.
  force160 = false;

  # (iface, network, bridge) -- channel/width are chosen by the scan at runtime.
  vaps = [
    { iface = "wlan0-0"; net = "cobalt-clients"; bridge = "ap-clients"; }
    { iface = "wlan0-1"; net = "cobalt-clients-vpn"; bridge = "ap-clients-vpn"; }
  ];

  hostapdConf = pkgs.writeShellScript "make-ap-hostapd-conf" ''
        set -euo pipefail
        YQ=${pkgs.yq-go}/bin/yq
        IW=${pkgs.iw}/bin/iw
        IP=${pkgs.iproute2}/bin/ip
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

        # ---- 5GHz channel scan (least-congested, avoid dossing neighbours) ----
        "$IP" link set ${scanIf} up 2>/dev/null || true
        sleep 3
        "$IW" dev ${scanIf} scan > /run/ap/scan.txt 2>/dev/null || true
        "$IP" link set ${scanIf} down 2>/dev/null || true

        c3680=$(grep -cE "freq: (5180|5200|5220|5240)" /run/ap/scan.txt 2>/dev/null || true)
        c5264=$(grep -cE "freq: (5260|5280|5300|5320)" /run/ap/scan.txt 2>/dev/null || true)
        c149=$(grep -cE "freq: (5745|5765|5785|5805)" /run/ap/scan.txt 2>/dev/null || true)
        c3680=''${c3680:-0}
        c5264=''${c5264:-0}
        c149=''${c149:-0}
        c160=$((c3680 + c5264))

        # 160MHz on channel 36 spans the DFS range 52-64, which the mt7925u
        # firmware cannot CAC (start_dfs_cac fails). Only select 160MHz when
        # force160 is enabled; otherwise fall straight to 80MHz.
        if [ "${if force160 then "1" else "0"}" = "1" ]; then
          channel=36; vht_w=2; vht_c=50; he_w=2; he_c=50
          dfs=$'ieee80211h=1\nieee80211d=1'
          echo "ap-conf: FORCED 160MHz ch36 (c160=$c160 c149=$c149)" >&2
        elif [ "$c3680" -le "$c149" ]; then
          channel=36; vht_w=1; vht_c=42; he_w=1; he_c=42
          dfs=""
          echo "ap-conf: 80MHz ch36 (c3680=$c3680 c149=$c149)" >&2
        else
          channel=149; vht_w=1; vht_c=155; he_w=1; he_c=155
          dfs=""
          echo "ap-conf: 80MHz ch149 (c3680=$c3680 c149=$c149)" >&2
        fi

        # ---- generate one config per SSID ----
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
    channel=$channel
    wmm_enabled=1
    country_code=NL
    ieee80211n=1
    ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40]
    ieee80211ac=1
    vht_oper_chwidth=$vht_w
    vht_oper_centr_freq_seg0_idx=$vht_c
    vht_capab=[SHORT-GI-80][SHORT-GI-160][MAX-MPDU-11454]
    ieee80211ax=1
    he_oper_chwidth=$he_w
    he_oper_centr_freq_seg0_idx=$he_c
    $dfs
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
      description = "Scan 5GHz and generate Nighthawk hostapd configs";
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
      description = "Create the Nighthawk AP and scan VAPs";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        phy=$(cat /sys/class/net/${wifiIf}/phy80211/name 2>/dev/null || echo phy0)
        for _ in $(seq 1 30); do
          if [ -d /sys/class/net/${scanIf} ]; then
            break
          fi
          ${pkgs.iw}/bin/iw phy "$phy" interface add ${scanIf} type station 2>/dev/null || true
          sleep 1
        done
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
