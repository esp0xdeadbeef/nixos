# Shared Wi-Fi AP builder for the cobalt nixos-shell AP VMs.
#
# One implementation of the hostapd plumbing (config generation, VAP creation,
# per-BSS systemd units, runtime SSID/PSK resolution) used by every AP radio,
# so a radio only declares its band settings and the plane set it carries. The
# plane set itself lives in ./wifi-ssids.nix.
#
# Each BSS runs its own hostapd process on its own VAP interface. This radio
# family cannot use a single hostapd with `bss=` sections: hostapd then derives
# the extra BSSIDs from the base MAC via bssid_mask, and the rt2800usb base
# (00:c0:ca:98:32:ff) is not aligned to the required mask, so hostapd refuses
# to start ("Start address must be the first address in the block"). Driving one
# process per VAP avoids BSSID derivation entirely.
#
# Usage:
#   (import ../wifi-ap.nix { inherit lib pkgs inputs relativeRepo; }) {
#     radio = { iface = "wlan0"; band = "2g"; channel = 11; country = "NL"; };
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
  # Radio / band description. The channel is a determined value, not scanned:
  #   "2g" -> hw_mode=g, 11n HT20 + short GI
  #   "5g" -> hw_mode=a, 11n + 11ac + 11ax, 80MHz
  radio
, # Planes to advertise on this radio (list from ./wifi-ssids.nix).
  planes
, # Deterministic SSID derivation order (from ./wifi-ssids.nix).
  deriveOrder
,
}:
let
  ssidList = relativeRepo.sourcePath "library/01-general/network/ssids.txt";
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

  # Shared 802.11 PHY settings (constant across the radio's BSSes). The channel
  # is a determined value; ap_isolate=1 keeps intra-BSS frames going through the
  # policy point instead of being bridged client-to-client at L2.
  #
  # noscan=1 on the 5GHz/80MHz radio: each plane runs its own hostapd process on
  # its own VAP on the same single-radio phy, and the pre-start HT scan picks a
  # primary channel per process. In an 80MHz block that choice is not unique
  # (36/40/44/48), so the first VAP can latch onto one primary (e.g. 40) while a
  # later one keeps the configured one (36). The two then disagree on the same
  # wiphy and the stray VAP silently stops beaconing its SSID. Skipping the scan
  # pins every VAP to radio.channel so they agree. The 2.4GHz single-channel case
  # has no such ambiguity and keeps the scan.
  phyLines =
    if radio.band == "2g" then
      ''
        hw_mode=g
        channel=${toString radio.channel}
        wmm_enabled=1
        country_code=${radio.country}
        ieee80211n=1
        ht_capab=[SHORT-GI-20]
        ap_isolate=1
      ''
    else
      ''
        hw_mode=a
        channel=${toString radio.channel}
        noscan=1
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
        ap_isolate=1
      '';

  servedPlanes = map (p: p.plane) planes;

  # Every served plane whose SSID is derived must have a declared derivation
  # order, otherwise the radio would guess an SSID. Fail closed instead.
  missingDerive = lib.filter (p: lib.hasPrefix "derive:" p.ssid && !(lib.elem p.plane deriveOrder)) planes;

  # Derive the served planes' SSIDs in the shared cross-radio order, so a radio
  # only derives what it carries and every radio still agrees on shared planes.
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

    # One config per VAP, one hostapd process per config.
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
      # disable_pmksa_caching: a stale AP-side PMKSA for a client's (often
      # randomised) MAC makes hostapd offer a cached PMKID that the client can
      # no longer use; the association then succeeds but the key handshake
      # never completes, which Android reports as "authorization problems".
      # Forcing a full SAE/4-way every time removes that failure mode.
      cat > /run/ap/$iface.conf <<EOF
    ctrl_interface=${ctrl}
    logger_stdout_level=0
    logger_syslog_level=0
    interface=$iface
    driver=nl80211
    ssid=$ssid
    ${phyLines}
    wpa=2
    wpa_key_mgmt=$keyMgmt
    wpa_pairwise=CCMP
    wpa_passphrase=$pass
    bridge=$bridge
    disable_pmksa_caching=1
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
          ExecStart = "${pkgs.hostapd}/bin/hostapd /run/ap/${v.iface}.conf";
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
      description = "Create the AP VAPs";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        phy=$(cat /sys/class/net/${radio.iface}/phy80211/name 2>/dev/null || echo phy0)
        ${vapCreate}
      '';
    };
  } // lib.listToAttrs (map mkApUnit vaps);
}
