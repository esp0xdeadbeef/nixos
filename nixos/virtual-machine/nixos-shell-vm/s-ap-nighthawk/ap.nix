{ config, lib, pkgs, inputs, relativeRepo, ... }:

# Nighthawk AXE3000 (mt7925u, 0846:9072) AP on a dedicated VM. The device is
# passed through via qemu-xhci and appears as wlan0 (phy0) in the VM's own
# netns. It owns the 5GHz and 6GHz clients / clients-vpn SSIDs and bridges them
# into VLAN 30 (clients) and VLAN 31 (clients-vpn) on the cobalt LAN trunk.
#
# WPA3-Personal (SAE) everywhere; 6GHz mandates SAE + PMF. SSIDs are derived
# deterministically from the SOPS seed so they match the cobalt router's
# derivation for the same planes.
let
  wifiIf = "wlan0";
  ctrl = "/run/ap";

  ssidList = inputs.wifi-ssids.outPath + "/ssids.txt";
  deriveSsid = pkgs.writeShellScript "derive-ssid" (
    builtins.readFile (relativeRepo.sourcePath "library/01-general/network/wifi-ssid-derive.sh")
  );

  # (iface, network, bridge, channel, extra hostapd lines)
  #
  # The mt7925u firmware exposes a single 5/6GHz radio: 5GHz and 6GHz cannot
  # be driven concurrently (the second channel context is rejected with
  # -EBUSY). Ship the two SSIDs on 5GHz (WiFi 6) as the stable default; the
  # 6GHz (WiFi 6E/7) VAPs are configurable but mutually exclusive with 5GHz.
  # 80 MHz channel width with 802.11n/ac/ax so the 5GHz link can actually
  # exceed ~200 Mbit/s (plain hw_mode=a without HT/VHT/HE caps the rate).
  # Channel 36 primary, 80 MHz centre = channel 42.
  fiveGhzExtra = ''
    ieee80211n=1
    ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40]
    ieee80211ac=1
    vht_oper_chwidth=1
    vht_oper_centr_freq_seg0_idx=42
    vht_capab=[SHORT-GI-80][MAX-MPDU-11454]
    ieee80211ax=1
    he_oper_chwidth=1
    he_oper_centr_freq_seg0_idx=42
  '';

  vaps = [
    { iface = "wlan0-0"; net = "cobalt-clients"; bridge = "ap-clients"; channel = 36; extra = fiveGhzExtra; }
    { iface = "wlan0-1"; net = "cobalt-clients-vpn"; bridge = "ap-clients-vpn"; channel = 36; extra = fiveGhzExtra; }
  ];

  hostapdConf = pkgs.writeShellScript "make-ap-hostapd-conf" ''
    set -euo pipefail
    YQ=${pkgs.yq-go}/bin/yq
    SEC=/run/secrets/cobalt-wifi
    seed=$("$YQ" -r '.seed' "$SEC")
    used=/run/ap/used-ssids
    rm -f "$used"
    ssid_clients=$(${deriveSsid} "$seed" cobalt-clients ${ssidList} "$used")
    ssid_cvpn=$(${deriveSsid} "$seed" cobalt-clients-vpn ${ssidList} "$used")
    pass_clients=$("$YQ" -r '.cobalt-clients.psk' "$SEC")
    pass_cvpn=$("$YQ" -r '.cobalt-clients-vpn.psk' "$SEC")
    mkdir -p ${ctrl}

    ${lib.concatMapStringsSep "\n" (v: ''
      case "${v.net}" in
        cobalt-clients) ssid="$ssid_clients"; pass="$pass_clients" ;;
        cobalt-clients-vpn) ssid="$ssid_cvpn"; pass="$pass_cvpn" ;;
      esac
      cat > ${ctrl}/${v.iface}.conf <<EOF
      ctrl_interface=${ctrl}
      logger_stdout_level=0
      logger_syslog_level=0
      interface=${v.iface}
      driver=nl80211
      ssid=$ssid
      hw_mode=a
      channel=${toString v.channel}
      wmm_enabled=1
      country_code=NL
      wpa=2
      wpa_key_mgmt=SAE
      wpa_pairwise=CCMP
      wpa_passphrase=$pass
      ieee80211w=2
      bridge=${v.bridge}
      ${v.extra}
      EOF
    '') vaps}
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
      description = "Generate Nighthawk hostapd AP configs";
      wantedBy = [ "multi-user.target" ];
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
