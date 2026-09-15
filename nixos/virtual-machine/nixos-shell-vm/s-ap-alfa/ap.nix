{ config, lib, pkgs, inputs, relativeRepo, ... }:

# 2.4GHz AP for the ALFA AWUS036NHA (rt2800usb, 148f:3070), USB-passthrough via
# qemu-xhci, appearing as wlan0 (phy0). It bridges every cobalt plane onto the
# LAN trunk (see ../wifi-ssids.nix) exactly like the 5GHz Nighthawk AP, so a
# client sees the same SSID set on both bands.
#
# Channel 11 is a determined value (the 2.4GHz band is scanned by hand to pick
# it, not by the AP at boot), so every reboot uses the same channel and clients
# never see the BSS move. Rates: 802.11n HT20 + short GI (RT3070 HT20/HT40).
# Client isolation is on so intra-BSS frames go through the policy point.
let
  spec = import ../wifi-ssids.nix;
in
(import ../wifi-ap.nix { inherit lib pkgs inputs relativeRepo; }) {
  radio = {
    iface = "wlan0";
    band = "2g";
    channel = 11;
    country = "NL";
  };
  inherit (spec) planes deriveOrder;
}
