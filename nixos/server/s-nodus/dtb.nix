{ config, lib, pkgs, ... }:

# Device tree for the Banana Pi BPI-R4 Pro 4E (MT7988A).
#
# Why we build the DTB ourselves:
#   * The board DTS (mt7988a-bananapi-bpi-r4-pro-4e.dts) only exists from
#     Linux 6.19 onward -> the nixpkgs default kernel (6.18.x) does NOT have it.
#   * Our kernel is linuxPackages_latest (7.2.x), which DOES have the source,
#     but this nixpkgs does not build/install DTBs for it here, so we cannot
#     rely on $kernel/dtbs.
#
# So we unpack the (official, mainline) kernel source and compile:
#   base  : mt7988a-bananapi-bpi-r4-pro-4e.dts      (official mainline board DTS)
#   overlay: mt7988a-bananapi-bpi-r4-pro-sd.dtso    (official mainline SD overlay)
# into a single resolved DTB. Nothing is vendored or decompiled from a
# downstream tree -- both files come straight from the kernel source we run.
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

  baseDts = "${dtsDir}/mt7988a-bananapi-bpi-r4-pro-4e.dts";
  sdDts = "${dtsDir}/mt7988a-bananapi-bpi-r4-pro-sd.dtso";

  # 1. compile the official base board DTB
  baseDtb = pkgs.deviceTree.compileDTS {
    name = "bpi-r4-pro-4e-base";
    dtsFile = baseDts;
    includePaths = dtIncludePaths;
  };

  # 2. compile the official SD overlay
  sdOverlay = pkgs.deviceTree.compileDTS {
    name = "bpi-r4-pro-sd-overlay";
    dtsFile = sdDts;
    includePaths = dtIncludePaths;
  };

  # 3. apply the overlay to the base DTB -> one resolved board DTB
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
