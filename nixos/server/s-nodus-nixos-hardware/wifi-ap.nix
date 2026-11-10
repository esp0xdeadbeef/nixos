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
# VLANs on the cobalt LAN trunk (br-cobalt-lan), exactly as the AP VMs do:
#   cobalt-clients      VLAN 30 -> bridge ap-clients
#   cobalt-clients-vpn  VLAN 31 -> bridge ap-clients-vpn
#   cobalt-mgmt         VLAN 10 -> bridge ap-mgmt
#   cobalt-unlock       VLAN 90 -> bridge ap-unlock
# so Wi-Fi is just another access medium onto the same tenants as the wired
# ports.  The host already terminates VLAN 30 as `vlan30`; the AP therefore
# reuses `vlan30` as its clients bridge (a port cannot belong to two bridges,
# and sharing the L2 is exactly the intent) and creates the other three.
#
# All interface names are <= IFNAMSIZ (15): plane bridges <= 14, VAPs are
# <base>-N, VLAN children cobalt-lan.NN are 13.
let
  spec = import ../../virtual-machine/nixos-shell-vm/wifi-ssids.nix;

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
  # the clients plane at `vlan30`; the other planes get their own bridges.
  bridgeFor = plane:
    if plane == "cobalt-clients" then "vlan30" else "ap-${lib.removePrefix "cobalt-" plane}";

  # Rewrite the plane set so each plane bridges onto the host's actual bridge.
  planes = map (p: p // { bridge = bridgeFor p.plane; }) spec.planes;

  # 6 GHz forbids pre-RSNA security methods, so only the SAE (WPA3) planes may be
  # advertised there; the WPA-PSK planes (mgmt, unlock) are 2.4/5 GHz only.
  saePlanes = builtins.filter (p: p.plane == "cobalt-clients" || p.plane == "cobalt-clients-vpn") planes;
in
{
  imports = [
    # 2.4 GHz and 5 GHz carry the full intent SSID set.
    (mkRadio { band = "2g"; iface = "wlp1s0"; channel = 6; planes = planes; })
    (mkRadio { band = "5g"; iface = "wlp1s-5"; channel = 36; vhtCenterIdx = 42; planes = planes; })
    # 6 GHz carries only the SAE planes (see saePlanes).
    (mkRadio { band = "6g"; iface = "wlp1s-6"; channel = 37; vhtCenterIdx = 47; planes = saePlanes; })
  ];

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
  systemd.services.ap-vap-extra = {
    description = "Create the MT7996 per-band AP base interfaces";
    wantedBy = [ "multi-user.target" ];
    after = [ "ap-planes.service" ];
    requires = [ "ap-planes.service" ];
    before = [ "ap-vap-wlp1s0.service" "ap-vap-wlp1s-5.service" "ap-vap-wlp1s-6.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
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
  # VLAN 30 already exists as `vlan30` (cobalt-bridges.nix), so the clients
  # plane reuses it; only the other three planes are built here.
  systemd.services.ap-planes = {
    description = "Create the cobalt AP VLAN children and plane bridges";
    wantedBy = [ "multi-user.target" ];
    before = [ "ap-vap-extra.service" ];
    after = [ "sys-subsystem-net-devices-br\\x2dcobalt\\x2dlan.device" ];
    requires = [ "sys-subsystem-net-devices-br\\x2dcobalt\\x2dlan.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 pkgs.gnugrep ];
    script = ''
      set -euo pipefail
      trunk=br-cobalt-lan
      # Locally-administered MACs so the bridges stay distinguishable.
      # (vlan|bridge name, vlan id (0 = plain bridge), mac)
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
}
