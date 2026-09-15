{ config, lib, pkgs, inputs, relativeRepo, ... }:

# 5GHz AP for the Nighthawk AXE3000 (mt7925u, 0846:9072), USB-passthrough via
# qemu-xhci, appearing as wlan0 (phy0). It bridges the cobalt planes it carries
# onto the LAN trunk (see ../wifi-ssids.nix) exactly like the 2.4GHz ALFA AP.
#
# Channel 36 @ 80MHz, 802.11n/ac/ax. 2.4GHz is deliberately NOT enabled here:
# concurrent 2.4+5GHz BSSes make the mt7925u firmware reset in a loop, so
# 2.4GHz coverage is provided by the separate ALFA radio.
#
# The mt7925u allows AP <= 4 but total <= 3 interfaces on one channel, so this
# radio carries at most three planes. It carries the two client-facing planes;
# mgmt and unlock stay on the 2.4GHz ALFA. Adding mgmt here is a one-line
# `serve` change plus an ap-mgmt bridge in default.nix (mirror the ALFA).
#
# Client isolation is on so intra-BSS frames go through the policy point
# instead of bridging client-to-client at L2.
let
  spec = import ../wifi-ssids.nix;
  serve = [
    "cobalt-clients"
    "cobalt-clients-vpn"
  ];
in
(import ../wifi-ap.nix { inherit lib pkgs inputs relativeRepo; }) {
  radio = {
    iface = "wlan0";
    band = "5g";
    channel = 36;
    vhtCenterIdx = 42;
    country = "NL";
  };
  planes = builtins.filter (p: builtins.elem p.plane serve) spec.planes;
  inherit (spec) deriveOrder;
}
