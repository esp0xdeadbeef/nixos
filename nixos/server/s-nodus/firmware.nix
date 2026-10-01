{ lib, stdenvNoCC, fetchurl, vendorImagePath ? null, vendorImageUrl ? null, vendorImageHash ? null }:

# Vendor firmware blobs for the BPI-R4 Pro 4E (MT7988A), sliced out of the
# vendor OpenWrt SD image.
#
# WHY THIS EXISTS
# ---------------
# The MT7988 BootROM loads BL2 from raw sector 34 of the SD card, and BL2 then
# loads the ARM-TF FIP (BL31 + BL33/U-Boot) from the GPT partition *named*
# `fip`.  Both are signed vendor firmware and cannot be built from source.  If
# the `fip` partition is missing, BL2 prints
#
#     Partition 'fip' not found
#     System halt!
#
# and never reaches U-Boot -- i.e. no NixOS at all.
#
# Only two blobs matter:
#
#   * bl2 : sectors 34..8191     (8158 sectors, ~4 MiB)
#   * fip : sectors 13312..21503 (8192 sectors, ~4 MiB)
#
# The vendor image's `ubootenv` (8192..9215) and `factory` (9216..13311)
# partitions are entirely zero in the shipped image -- the board's U-Boot uses
# its built-in environment -- so nothing is taken from them.
#
# INPUT
# -----
# Banana Pi's download URLs are unstable and the image is not redistributable,
# so the vendor .img is passed in explicitly (local path or URL):
#
#   nix-build -E 'with import <nixpkgs> {};
#     callPackage ./firmware.nix { vendorImagePath = /path/to/vendor.img; }'
#
# mk-sd-image.sh wires this up automatically; see ./README.md.
let
  vendorImage =
    if vendorImagePath != null then
      if builtins.pathExists vendorImagePath then
        vendorImagePath
      else
        throw "firmware.nix: vendorImagePath ${vendorImagePath} does not exist"
    else if vendorImageUrl != null then
      if vendorImageHash != null then
        fetchurl
          {
            name = "BPI-R4Pro-4E-sdcard-vendor.img";
            url = vendorImageUrl;
            hash = vendorImageHash;
          }
      else
        throw "firmware.nix: vendorImageHash is required with vendorImageUrl"
    else
      throw "firmware.nix: pass either vendorImagePath or vendorImageUrl";

  # GPT geometry of the vendor SD image (512-byte sectors).  Verified against
  # BPI-R4Pro-4E-BE14-MT76-OpenWRT24.10-sdcard-260325.img.
  bl2Start = 34;
  bl2Count = 8158;
  fipStart = 13312;
  fipCount = 8192;
in
stdenvNoCC.mkDerivation {
  pname = "bpi-r4-pro-4e-firmware";
  version = "openwrt-24.10-260325";

  dontUnpack = true;
  dontBuild = true;

  # Byte extraction from fixed ranges: the output is a pure function of the
  # vendor image bytes, so a fixed-output derivation is correct + cacheable.
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  # Update from the build's hash-mismatch error if the vendor image changes.
  outputHash = "sha256-najvfemeJdmfMj1ALR4ib0EKWTvjYbluEW461g1XmXg=";

  installPhase = ''
    runHook preInstall
    mkdir -p $out

    dd if=${vendorImage} of=$out/bl2.bin bs=512 skip=${toString bl2Start} \
       count=${toString bl2Count} status=none
    dd if=${vendorImage} of=$out/fip.bin bs=512 skip=${toString fipStart} \
       count=${toString fipCount} status=none

    # Fail loudly if this is not the image we think it is.
    head -c 11 $out/bl2.bin | grep -q 'SDMMC_BOOT' \
      || { echo "bl2.bin: missing SDMMC_BOOT header -- wrong vendor image?" >&2; exit 1; }
    [ "$(od -An -tx1 -N4 $out/fip.bin | tr -d ' \n')" = "010064aa" ] \
      || { echo "fip.bin: missing FIP magic -- wrong vendor image?" >&2; exit 1; }

    runHook postInstall
  '';

  impureEnvVars = lib.fetchers.proxyImpureEnvVars;

  passthru = { inherit bl2Start bl2Count fipStart fipCount; };

  meta = with lib; {
    description = "Signed BL2 + ARM-TF FIP firmware for the BPI-R4 Pro 4E (MT7988A)";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
