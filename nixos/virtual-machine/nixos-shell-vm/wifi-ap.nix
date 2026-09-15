# Shared Wi-Fi AP builder for the cobalt nixos-shell AP VMs.
#
# One implementation of the hostapd plumbing (config generation, VAP creation,
# per-BSS systemd units, runtime SSID/PSK resolution) used by every AP radio,
# so a radio only declares its band settings and the plane set it carries. The
# plane set itself lives in ./wifi-ssids.nix.
#
# Usage:
#   (import ../wifi-ap.nix { inherit lib pkgs inputs relativeRepo; }) {
#     radio = { iface = "wlan0"; scanIf = "wlan0-scan"; band = "2g"; ... };
#     planes = spec.planes;       # from ../wifi-ssids.nix
#     deriveOrder = spec.deriveOrder;
#   }
#
# The builder returns a NixOS module fragment ({ systemd.services = ...; }).
{ lib
, pkgs
, inputs
, relativeRepo
}:
{
  # Radio / band description. `band` selects the hostapd rate configuration:
  #   "2g" -> hw_mode=g, optional auto channel (1/6/11 scan), 11n HT20 + short GI
  #   "5g" -> hw_mode=a, fixed channel, 11n + 11ac + 11ax, 80MHz
  radio
, # Planes to advertise on this radio (list from ./wifi-ssids.nix).
  planes
, # Deterministic SSID derivation order (from ./wifi-ssids.nix).
  deriveOrder
,
}:
let
  ssidList = inputs.wifi-ssids.outPath + "/ssids.txt";
  deriveSsid = pkgs.writeShellScript "derive-ssid" (
    builtins.readFile (relativeRepo.sourcePath "library/01-general/network/wifi-ssid-derive.sh")
  );

  ctrl = "/run/ap";

  # Give each plane a VAP interface. The first plane uses the radio's base
  # interface (the rt2800usb/mt7925u bring the base up as wlan0 reliably);
  # the rest are created as wlan0-1, wlan0-2, ...
  vaps = lib.imap0
    (i: p: p // { iface = if i == 0 then radio.iface else "${radio.iface}-${toString i}"; })
    planes;

  varName = plane: lib.replaceStrings [ "-" ] [ "_" ] plane;

  # "iface:plane:bridge:keyMgmt" specs consumed by the conf loop.
  confSpecs = lib.concatMapStringsSep " " (v: "\"${v.iface}:${v.plane}:${v.bridge}:${v.keyMgmt}\"") vaps;

  # The 802.11 PHY lines differ per band but are constant across a radio's BSSes.
  phyLines =
    if radio.band == "2g" then
      ''
        hw_mode=g
        channel=$ch
        wmm_enabled=1
        country_code=${radio.country}
        ieee80211n=1
        ht_capab=[SHORT-GI-20]
      ''
    else
      ''
        hw_mode=a
        channel=${toString radio.channel}
        wmm_enabled=1
        country_code=${radio.country}
        ieee80211n=1
        ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40]
        ieee80211ac=1
        vht_oper_chwidth=1
        vht_oper_centr_freq_seg0_idx=${toString radio.vhtCenterIdx}
        vht_capab=[SHORT-GI-80][SHORT-GI-160][MAX-MPDU-11454]
        ieee80211ax=1
        he_oper_chwidth=1
        he_oper_centr_freq_seg0_idx=${toString radio.vhtCenterIdx}
      '';

  channelScan =
    if radio.band == "2g" && radio ? scanIf then
      ''
        # Pick the least-congested 2.4GHz channel (1/6/11) from a one-shot scan.
        ${pkgs.iproute2}/bin/ip link set ${radio.scanIf} up 2>/dev/null || true
        sleep 2
        ${pkgs.iw}/bin/iw dev ${radio.scanIf} scan > /run/ap/scan.txt 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link set ${radio.scanIf} down 2>/dev/null || true

        c1=$(${pkgs.gnugrep}/bin/grep -c "freq: 2412" /run/ap/scan.txt || true)
        c6=$(${pkgs.gnugrep}/bin/grep -c "freq: 2437" /run/ap/scan.txt || true)
        c11=$(${pkgs.gnugrep}/bin/grep -c "freq: 2462" /run/ap/scan.txt || true)

        bestfreq=2412
        bestn=$c1
        if [ "$c6" -lt "$bestn" ]; then bestfreq=2437; bestn=$c6; fi
        if [ "$c11" -lt "$bestn" ]; then bestfreq=2462; bestn=$c11; fi
        case "$bestfreq" in
          2412) ch=1 ;;
          2437) ch=6 ;;
          2462) ch=11 ;;
          *) ch=6 ;;
        esac
      ''
    else
      "ch=${toString (radio.channel or 0)}";

  servedPlanes = map (p: p.plane) planes;

  # Every served plane whose SSID is derived must have a declared derivation
  # order, otherwise the radio would guess an SSID. Fail closed instead.
  missingDerive = lib.filter (p: lib.hasPrefix "derive:" p.ssid && !(lib.elem p.plane deriveOrder)) planes;

  # Derive the served planes' SSIDs once, in the shared cross-radio order, so a
  # radio only derives what it actually carries and every radio still agrees.
  deriveLines = lib.concatMapStrings
    (plane: ''
      ssid_${varName plane}=$(${deriveSsid} "$seed" ${plane} ${ssidList} "$used")
    '')
    (lib.filter (p: lib.elem p servedPlanes) deriveOrder);

  secretSsidLines = lib.concatMapStrings
    (p:
      lib.optionalString (lib.hasPrefix "secret:" p.ssid) ''
        ssid_${varName p.plane}=$("$YQ" -r '.${lib.removePrefix "secret:" p.ssid}.ssid' "$SEC")
      '')
    planes;

  pskLines = lib.concatMapStrings
    (p: ''
      pass_${varName p.plane}=$("$YQ" -r '.${p.pskKey}.psk' "$SEC")
    '')
    planes;

  caseArms = lib.concatMapStrings
    (p: ''
      ${p.plane}) ssid="$ssid_${varName p.plane}"; pass="$pass_${varName p.plane}" ;;
    '')
    planes;

  hostapdConf = pkgs.writeShellScript "make-ap-hostapd-conf" ''
    set -euo pipefail
    ${channelScan}

    YQ=${pkgs.yq-go}/bin/yq
    SEC=/run/secrets/cobalt-wifi
    seed=$("$YQ" -r '.seed' "$SEC")
    used=/run/ap/used-ssids
    rm -f "$used"

    # Derive shared planes first, in the order every radio must agree on.
    ${deriveLines}
    # Fixed (non-derived) SSIDs.
    ${secretSsidLines}
    # Passphrases.
    ${pskLines}

    for spec in ${confSpecs}; do
      iface="''${spec%%:*}"
      rest="''${spec#*:}"
      plane="''${rest%%:*}"
      rest="''${rest#*:}"
      bridge="''${rest%%:*}"
      keyMgmt="''${rest#*:}"
      case "$plane" in
        ${caseArms}
      esac
      cat > /run/ap/$iface.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=$iface
    driver=nl80211
    ssid=$ssid
    ${phyLines}
    ap_isolate=1
    wpa=2
    wpa_key_mgmt=$keyMgmt
    wpa_pairwise=CCMP
    wpa_passphrase=$pass
    bridge=$bridge
    EOF
      # WPA3/SAE requires protected management frames.
      if [ "$keyMgmt" = "SAE" ]; then
        echo "ieee80211w=2" >> /run/ap/$iface.conf
      fi
    done
  '';

  # Create every VAP that is not the radio's base interface.
  vapCreateIndexes = lib.range 1 (lib.length vaps - 1);
  ifaceOf = i: (lib.elemAt vaps i).iface;
  vapCreate = lib.concatMapStrings
    (i: ''
      for _ in $(seq 1 30); do
        if [ -d /sys/class/net/${ifaceOf i} ]; then break; fi
        ${pkgs.iw}/bin/iw phy "$phy" interface add ${ifaceOf i} type __ap 2>/dev/null || true
        sleep 1
      done
    '')
    vapCreateIndexes;
  scanCreate = lib.optionalString (radio ? scanIf) ''
    for _ in $(seq 1 30); do
      if [ -d /sys/class/net/${radio.scanIf} ]; then break; fi
      ${pkgs.iw}/bin/iw phy "$phy" interface add ${radio.scanIf} type station 2>/dev/null || true
      sleep 1
    done
  '';

  mkApUnit =
    v: {
      name = "ap-${v.iface}";
      value = {
        description = "WiFi AP ${v.iface} (${v.plane}) on bridge ${v.bridge}";
        wantedBy = [ "multi-user.target" ];
        after = [ "ap-conf.service" "ap-vap.service" ];
        requires = [ "ap-conf.service" "ap-vap.service" ];
        path = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.iproute2
        ];
        serviceConfig = {
          ExecStart = "${pkgs.hostapd}/bin/hostapd -i ${v.iface} ${ctrl}/${v.iface}.conf";
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
assert lib.assertMsg (missingDerive == [ ])
  "wifi-ap: planes missing from deriveOrder: ${toString (map (p: p.plane) missingDerive)}";
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
      description = "Create the AP and scan VAPs";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        phy=$(cat /sys/class/net/${radio.iface}/phy80211/name 2>/dev/null || echo phy0)
        ${vapCreate}
        ${scanCreate}
      '';
    };
  } // lib.listToAttrs (map mkApUnit vaps);
}
