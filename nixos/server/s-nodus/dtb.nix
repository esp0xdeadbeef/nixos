{ config, lib, pkgs, ... }:

# Device tree for the BPI-R4 Pro 4E (MT7988A), for the patched 6.18 board kernel.
#
# We ship a SELF-CONTAINED board DTS (./dtb/mt7988a-bananapi-bpi-r4-pro-4e-sd.dts)
# and compile it directly with dtc, instead of building it from the kernel
# source.  Two reasons:
#
#   1. The board DTS (mt7988a-bananapi-bpi-r4-pro-4e.dts) only landed upstream in
#      Linux 6.19, and we run the 6.18 board kernel (kernel.nix) for its MT7988
#      USXGMII/SerDes + MxL86252 support -- so the kernel source has no 4E DTS.
#   2. The mainline 6.19 board dtsi does not compile against the 6.18 mt7988a.dtsi
#      (symbol drift, e.g. ssusb0).  A resolved, self-contained DTS sidesteps all
#      of that; it is the same approach the ly4096x/BananaPi-R4-Pro-8X-OS port
#      uses.
#
# Provenance of ./dtb/...dts: `dtc -I dtb -O dts` of the overlay-resolved DTB
# this repo produced for the mainline kernel (mainline board dtsi + our
# lan-port-map fragment + the mainline SD overlay), i.e. exactly the tree that
# already runs, frozen into one file.  It carries our hardware fixes:
#   * internal switch: port 0 (lan5, the one 1G RJ45) only -- this is an
#     8X-population board, ports 1..3 have no jacks;
#   * the MxL86252 in MAINLINE port numbering (copper ports 1..4 = mxl_lan0..3,
#     CPU port 9, SFP port 13), firmware 1.0.85.
let
  lanPortMap = import ./lan-port-map.nix { inherit lib; };
in
{
  hardware.deviceTree = {
    enable = true;
    name = "mediatek/mt7988a-bananapi-bpi-r4-pro-4e-sd.dtb";

    # Replace the kernel's (absent) bundled dtbs with our resolved one.
    dtbSource = pkgs.runCommand "bpi-r4-pro-dtbs"
      {
        nativeBuildInputs = [ pkgs.dtc ];
      } ''
      mkdir -p $out/mediatek
      dtc -I dts -O dtb -o "$out/mediatek/mt7988a-bananapi-bpi-r4-pro-4e-sd.dtb" \
        ${./dtb/mt7988a-bananapi-bpi-r4-pro-4e-sd.dts}
    '';
  };
}
