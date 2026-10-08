{ config, lib, pkgs, ... }:

# Device tree for the Banana Pi BPI-R4 Pro 4E (MT7988A).
#
# Why we build the DTB ourselves:
#   * Our kernel is linuxPackages_latest (7.2.x), which has the mainline board
#     DTS source, but this nixpkgs does not build/install DTBs for it here, so
#     we cannot rely on $kernel/dtbs.
#
# We compile:
#   base  : the official mainline board dtsi, plus a generated fragment that
#           describes the jacks of BOTH switches on this board (see
#           ./lan-port-map.nix for authority and provenance).
#   overlay: mt7988a-bananapi-bpi-r4-pro-sd.dtso (official mainline SD overlay)
# and apply the overlay with fdtoverlay to get one resolved board DTB.
#
# The board fragment is part of the BASE compilation unit (not an fdtoverlay)
# on purpose: fdtoverlay cannot resolve a phandle introduced by the overlay
# itself (`&gbeN_led0_pins`) nor /delete-node/, both of which the map needs.
# The upstream node text is vendored from the vendor 4E board DTS
# (BPI-SINOVOIP/BPI-R4PRO-4E-OPENWRT, GPL-2.0 OR MIT) and adapted to mainline.
let
  kernel = config.boot.kernelPackages.kernel;

  # Unpacked kernel source tree (the .src attr is a .tar.xz, not a directory).
  kernelSource = pkgs.runCommand "linux-source-unpacked" { } ''
    mkdir -p $out
    tar -xf ${kernel.src} -C $out --strip-components=1
  '';

  dtsDir = "${kernelSource}/arch/arm64/boot/dts/mediatek";

  # Include paths the kernel's .dts/.dtso files expect.
  dtIncludePaths = [
    dtsDir
    "${kernelSource}/include"
    "${kernelSource}/scripts/dtc/include-prefixes"
  ];

  # The single source of truth for the physical port map (DT labels + roles).
  lanPortMap = import ./lan-port-map.nix { inherit lib; };

  # Our base DTS: the official mainline board dtsi plus the generated fragment.
  # We include the board dtsi (not the -4e.dts, which carries its own /dts-v1/)
  # and set the 4E model, exactly as the upstream -4e.dts does.
  baseDts = pkgs.writeText "mt7988a-bananapi-bpi-r4-pro-4e-s-nodus.dts" ''
    /dts-v1/;

    #include "mt7988a-bananapi-bpi-r4-pro.dtsi"

    / {
      model = "Bananapi BPI-R4 Pro 4E";
      compatible = "bananapi,bpi-r4-pro-4e",
                   "bananapi,bpi-r4-pro",
                   "mediatek,mt7988a";
    };

    ${lanPortMap.baseFragment}
  '';

  # 1. compile our base board DTB
  baseDtb = pkgs.deviceTree.compileDTS {
    name = "bpi-r4-pro-4e-base";
    dtsFile = baseDts;
    includePaths = dtIncludePaths;
  };

  # 2. compile the official SD overlay
  sdDts = "${dtsDir}/mt7988a-bananapi-bpi-r4-pro-sd.dtso";
  sdOverlay = pkgs.deviceTree.compileDTS {
    name = "bpi-r4-pro-sd-overlay";
    dtsFile = sdDts;
    includePaths = dtIncludePaths;
  };

  # 3. apply the SD overlay to the base DTB -> one resolved board DTB
  resolvedDtb = pkgs.runCommand "mt7988a-bananapi-bpi-r4-pro-4e-sd.dtb"
    {
      nativeBuildInputs = [ pkgs.dtc ];
    } ''
    fdtoverlay -i ${baseDtb} -o "$out" ${sdOverlay}
  '';
in
{
  # Point the kernel at our resolved DTB (installed to /boot/dtbs by NixOS).
  hardware.deviceTree = {
    enable = true;
    name = "mediatek/mt7988a-bananapi-bpi-r4-pro-4e-sd.dtb";

    # Replace the kernel's (absent) bundled dtbs with our resolved one.
    dtbSource = pkgs.runCommand "bpi-r4-pro-dtbs" { } ''
      mkdir -p $out/mediatek
      cp ${resolvedDtb} $out/mediatek/mt7988a-bananapi-bpi-r4-pro-4e-sd.dtb
    '';
  };
}
