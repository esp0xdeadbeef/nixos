{ config, lib, pkgs, inputs, relativeRepo, ... }:

# Host-level Wi-Fi AP for s-nodus using the on-board MediaTek MT7996
# (Wi-Fi 7, tri-band).  This reuses the SAME implementation the cobalt AP VMs
# (s-ap-nighthawk / s-ap-alfa) run: ../wifi-ap.nix (the shared hostapd builder,
# SSID derivation, VAP creation, runtime PSK from /run/secrets/cobalt-wifi) and
# ../wifi-ssids.nix (the plane set), but hosted on the s-nodus host rather than
# in a VM.  The MT7996 has full mainline AP support (driver mt7996e: 3 radios,
# 19 interfaces/band), so no kernel patches are required (unlike the USB mt7925
# in the Nighthawk VM).
#
# Topology: the AP bridges its BSSes onto the cobalt tenant planes, which are
# VLANs on the cobalt LAN trunk, exactly as the AP VMs do:
#   cobalt-clients      VLAN 30 -> clients bridge (vlan30)
#   cobalt-clients-vpn  VLAN 31 -> bridge ap-clients-vpn
#   cobalt-mgmt         VLAN 10 -> bridge ap-mgmt
#   cobalt-unlock       VLAN 90 -> bridge ap-unlock
# so Wi-Fi is just another access medium onto the same tenants as the wired
# ports.  The host already terminates VLAN 30 as `vlan30`; the AP therefore
# reuses `vlan30` as its clients bridge (a port cannot belong to two bridges,
# and sharing the L2 is exactly the intent) and creates the other three.
#
# WHICH trunk those VLANs come off is realization data, not a constant: prod
# terminates the access VLANs off `br-cobalt-lan` (fed by the router VM's vhost
# tap), while the container shapes (router-new-test) hand the physical trunk
# jack `mxl_lan0` to `br-lan-trunk` instead (prod-network inventory
# `uplinks.trunk.bridge`) and leave `br-cobalt-lan` with no member at all.
# Building the AP VLAN children on `br-cobalt-lan` there yields NO-CARRIER
# bridges, and every AP's preStart then loops forever waiting for `state UP`.
# `trunkBridge` therefore defaults to the prod value so this module's prod
# output is unchanged, and a container-shaped host overrides it.
#
# All interface names are <= IFNAMSIZ (15): plane bridges <= 14, VAPs are
# <base>-N, VLAN children cobalt-lan.NN are 13.
let
  spec = import ../../virtual-machine/nixos-shell-vm/wifi-ssids.nix;
  cfg = config.local.sNodusWifi;

  apModule = import ../../virtual-machine/nixos-shell-vm/wifi-ap.nix {
    inherit lib pkgs inputs relativeRepo;
  };

  # Interface name budget (IFNAMSIZ): <base>-N VAPs, plane bridges <= 14.
  mkRadio =
    { band, iface, channel, vhtCenterIdx ? null, planes }:
    apModule {
      radio = { inherit band iface channel country; } // lib.optionalAttrs (vhtCenterIdx != null) { inherit vhtCenterIdx; };
      inherit planes;
      inherit (spec) deriveOrder;
    };

  country = "NL";

  # The builder bridges each BSS onto the bridge named in wifi-ssids.nix.  On
  # the host the clients plane (VLAN 30) is already terminated as the `vlan30`
  # bridge by cobalt-bridges.nix, and a port cannot be in two bridges, so point
  # the clients plane at that bridge; the other planes get their own bridges.
  bridgeFor = plane:
    if plane == "cobalt-clients" then cfg.clientsBridge else "ap-${lib.removePrefix "cobalt-" plane}";

  # Rewrite the plane set so each plane bridges onto the host's actual bridge.
  planes = map (p: p // { bridge = bridgeFor p.plane; }) spec.planes;

  # 6 GHz forbids pre-RSNA security methods, so only the SAE (WPA3) planes may be
  # advertised there; the WPA-PSK planes (mgmt, unlock) are 2.4/5 GHz only.
  saePlanes = builtins.filter (p: p.plane == "cobalt-clients" || p.plane == "cobalt-clients-vpn") planes;
in
{
  options.local.sNodusWifi = {
    trunkBridge = lib.mkOption {
      type = lib.types.str;
      default = "br-cobalt-lan";
      description = ''
        Bridge the access VLANs are terminated on, i.e. the bridge that carries
        the cobalt LAN trunk into the router.

        This is realization data from the deployment inventory
        (prod-network/*/inventory-cobalt.nix `uplinks.trunk.bridge`), not a
        constant: prod terminates the access VLANs off `br-cobalt-lan` (kept
        alive by the router VM's vhost tap), while the container shapes give
        the physical trunk port `mxl_lan0` to `br-lan-trunk` and leave
        `br-cobalt-lan` memberless.

        The default preserves the production wiring, so a host that does not
        override this emits exactly the units it always did.
      '';
    };

    clientsBridge = lib.mkOption {
      type = lib.types.str;
      default = "vlan30";
      description = ''
        Bridge the `cobalt-clients` BSSes are enslaved to. The host already
        terminates clients VLAN 30 as this bridge, and a port cannot belong to
        two bridges, so the AP shares it rather than creating its own.
      '';
    };
  };

  imports = [
    # 2.4 GHz and 5 GHz carry the full intent SSID set.
    (mkRadio { band = "2g"; iface = "wlp1s0"; channel = 6; planes = planes; })
    (mkRadio { band = "5g"; iface = "wlp1s-5"; channel = 36; vhtCenterIdx = 42; planes = planes; })
    # 6 GHz carries only the SAE planes (see saePlanes).
    (mkRadio { band = "6g"; iface = "wlp1s-6"; channel = 37; vhtCenterIdx = 47; planes = saePlanes; })
  ];

  config = {

    # Wi-Fi firmware (MT7996 blobs).
    hardware.enableRedistributableFirmware = true;

    # The cobalt Wi-Fi secret (same file/fields the AP VMs read).
    sops.secrets."cobalt-wifi" = {
      sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-wifi.yaml";
      key = "";
      path = "/run/secrets/cobalt-wifi";
    };

    # MT7996 exposes a single netdev (wlp1s0); the builder manages VAPs on the
    # radio's base interface but assumes that base already exists (it reads the
    # phy from /sys/class/net/<base>/phy80211).  For 5/6 GHz the base interfaces
    # (wlp1s-5 / wlp1s-6) must be created on phy0 first.  ap-vap-extra runs before
    # ap-vap and the per-BSS hostapd units.
    #
    # It `wants` but does NOT `require` ap-planes.  This unit only creates
    # interfaces on phy0 and touches no bridge, so the plane bridges are
    # irrelevant to it -- and a hard `requires` here was the cascade that took
    # 5 GHz and 6 GHz down together: every BSS `requires` ap-vap-<radio>,
    # which `requires` ap-vap-extra, which `requires` ap-planes.  When
    # ap-planes failed at boot, that failure propagated all the way up and
    # wlp1s-5/wlp1s-6 were never created (measured on s-nodus: only wlp1s0
    # existed, and all 5/6 GHz units were dead).  `wants` still pulls ap-planes
    # in and keeps the ordering, but a bridge failure can no longer kill the
    # per-band interfaces.
    #
    # Restart=on-failure: a oneshot that fails once (radio not yet probed, phy
    # busy) now retries by itself instead of needing `systemctl start` by hand.
    # Each pass recreates whatever is missing and leaves existing interfaces
    # alone, so retrying is idempotent.
    systemd.services.ap-vap-extra = {
      description = "Create the MT7996 per-band AP base interfaces";
      wantedBy = [ "multi-user.target" ];
      after = [ "ap-planes.service" ];
      wants = [ "ap-planes.service" ];
      before = [ "ap-vap-wlp1s0.service" "ap-vap-wlp1s-5.service" "ap-vap-wlp1s-6.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 10;
      };
      script = ''
        set -euo pipefail
        base=$(cat /sys/class/net/wlp1s0/address 2>/dev/null || echo 00:00:00:00:00:00)
        macAddr() {
          local h=$(printf '%s' "$1" | cksum | ${pkgs.gawk}/bin/awk '{print $1}')
          ${pkgs.gawk}/bin/awk -v h="$h" -F: '{printf "%02x:%s:%s:%s:%02x:%02x\n", (strtonum("0x" $1)+2), $2,$3,$4, (h%256), (int(h/256)%256)}' <<< "$base"
        }
        for iface in wlp1s-5 wlp1s-6; do
          for _ in $(seq 1 30); do
            [ -d /sys/class/net/$iface ] && break
            ${pkgs.iw}/bin/iw phy phy0 interface add $iface type __ap 2>/dev/null || true
            sleep 1
          done
          # Distinct locally-administered MAC; the phy otherwise shares the base
          # MAC and the kernel refuses to bring more than one interface up.
          ${pkgs.iproute2}/bin/ip link set $iface down 2>/dev/null || true
          ${pkgs.iproute2}/bin/ip link set $iface address $(macAddr $iface) 2>/dev/null || true
        done

        # Hard post-condition.  Without it this unit "succeeds" after silently
        # failing to create the interface (the `|| true` in the loop swallows
        # the error), and the first visible symptom is 5/6 GHz simply missing,
        # with no failed unit to point at.  Failing here makes the cause
        # explicit and lets Restart=on-failure retry once the phy is ready.
        missing=""
        for iface in wlp1s-5 wlp1s-6; do
          [ -d /sys/class/net/$iface ] || missing="$missing $iface"
        done
        if [ -n "$missing" ]; then
          echo "ap-vap-extra: could not create:$missing (phy0 not ready?)" >&2
          exit 1
        fi
      '';
    };

    # Host-side trunk VLAN children + plane bridges the AP bridges into.
    #
    # These are created by a systemd oneshot running `ip`, NOT by
    # systemd-networkd netdevs: networkd does not reliably create a bridge plus
    # the VLAN children enslaved to it in a single pass, so on some boots
    # cobalt-lan.{10,31,90} and the ap-* bridges never come up -- the bridges then
    # stay NO-CARRIER and every BSS whose preStart waits for `bridge state UP`
    # fails to start (the whole 2.4/5 GHz AP silently disappears).  Creating them
    # explicitly is deterministic and orderable.
    #
    # VLAN 30 already exists as the clients bridge (cobalt-bridges.nix), so the
    # clients plane reuses it; only the other three planes are built here. The
    # trunk these VLAN children are created on follows `local.sNodusWifi.trunkBridge`
    # so a container-shaped host (trial) builds them on the bridge that actually
    # carries the physical trunk instead of the memberless `br-cobalt-lan`.
    #
    # The trunk is waited for INSIDE the script, not by a unit dependency.
    # A `requires`/`after` on `sys-subsystem-net-devices-<trunk>.device` looks
    # correct but is not: the bridge is a virtual netdev created by
    # systemd-networkd at runtime, so its udev device unit does not exist yet
    # when systemd builds the boot transaction.  systemd then records a
    # not-found dependency and fails this job at transaction time -- even
    # though the device unit goes `active (plugged)` 78s earlier on this host
    # (boot 47f2b654: br-cobalt-lan plugged 06:05:07, "Dependency failed for
    # ap-planes.service" 06:06:25).  The job never retries, so ap-mgmt /
    # ap-clients-vpn / ap-unlock were never created, every BSS bridged onto
    # them looped forever in start-pre waiting for `state UP`, and ap-vap-extra
    # (requires=ap-planes) also failed -- taking 5/6 GHz down with it because
    # wlp1s-5/wlp1s-6 were never made.  Polling the link is what ap-vap-extra
    # already does for the base interfaces: deterministic and recoverable.
    systemd.services.ap-planes = {
      description = "Create the cobalt AP VLAN children and plane bridges";
      wantedBy = [ "multi-user.target" ];
      before = [ "ap-vap-extra.service" ];
      # Order against the device unit when it exists, but do NOT require it: a
      # missing-at-transaction-time device unit must not fail the job.
      after = [ "sys-subsystem-net-devices-${cfg.trunkBridge}.device" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Self-heal if the trunk bridge appears late (networkd slow, or the
        # board boots before the cobalt VM taps br-cobalt-lan): retry instead of
        # leaving the plane bridges missing until someone notices.
        Restart = "on-failure";
        RestartSec = 10;
      };
      path = [ pkgs.iproute2 pkgs.gnugrep pkgs.coreutils ];
      script = ''
        set -euo pipefail
        trunk=${cfg.trunkBridge}

        # Bounded wait for the trunk bridge networkd creates.  ~60s is well
        # inside the boot budget and far longer than networkd needs to create
        # a bridge from its .netdev; failing loudly beats silently starting the
        # VLAN children on a link that does not exist (ip link add would then
        # create link-less VLANs that never carry a frame).
        for _ in $(seq 1 60); do
          ip link show "$trunk" >/dev/null 2>&1 && break
          sleep 1
        done
        if ! ip link show "$trunk" >/dev/null 2>&1; then
          echo "ap-planes: trunk bridge $trunk never appeared" >&2
          exit 1
        fi
        # (vlan child, vlan id, plane bridge) triples, matching the plane set
        # in wifi-ssids.nix.  The clients plane is NOT here: it bridges onto
        # the host's own vlan30 (see clientsBridge).
        for spec in \
          "cobalt-lan.10 10 ap-mgmt" \
          "cobalt-lan.31 31 ap-clients-vpn" \
          "cobalt-lan.90 90 ap-unlock"; do
          set -- $spec
          vlan_if=$1; vlan_id=$2; br=$3
          ip link show "$br" >/dev/null 2>&1 || ip link add name "$br" type bridge
          ip link set "$br" up
          ip link show "$vlan_if" >/dev/null 2>&1 || ip link add link "$trunk" name "$vlan_if" type vlan id "$vlan_id"
          ip link set "$vlan_if" up
          ip link set "$vlan_if" master "$br"
        done
        for br in ap-mgmt ap-clients-vpn ap-unlock; do
          ip link set "$br" up
        done
      '';
    };
  };
}
