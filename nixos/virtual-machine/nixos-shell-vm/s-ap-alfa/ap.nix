{ config, lib, pkgs, inputs, relativeRepo, ... }:

# 2.4GHz AP for the ALFA AWUS036NHA (rt2800usb, 148f:3070), USB-passthrough via
# qemu-xhci, appearing as wlan0 (phy0). It bridges every cobalt plane onto the
# LAN trunk (see ../wifi-ssids.nix) exactly like the 5GHz Nighthawk AP, so a
# client sees the same SSID set on both bands.
#
# Rates: 802.11n HT20 + short GI on the 2.4GHz band (the RT3070 supports
# HT20/HT40). Client isolation is on so intra-BSS frames go through the policy
# point instead of bridging client-to-client at L2.
let
  spec = import ../wifi-ssids.nix;
in
(import ../wifi-ap.nix { inherit lib pkgs inputs relativeRepo; }) {
  radio = {
    iface = "wlan0";
    scanIf = "wlan0-scan";
    band = "2g";
    country = "NL";
  };
  inherit (spec) planes deriveOrder;
}
