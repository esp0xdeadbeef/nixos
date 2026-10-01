{ disk ? "/dev/sda", ... }:

# s-nodus storage layout -- microSD only. NEVER SPI-NAND or eMMC.
#
# The layout is NOT a free choice.  Two separate pieces of the MediaTek boot
# chain look up GPT partitions *by name*, at *fixed* places:
#
#   * BL2 (SD preloader, /dev/mmcblk0 sector 34) reads the GPT and searches for
#     a partition named `fip`; if it is absent it prints
#         "Partition 'fip' not found"
#     then "System halt!" -- never reaching U-Boot.  (Verified: those strings
#     are in the vendor BL2 blob.)
#
#   * The board's stock OpenWrt U-Boot then boots the NixOS FIT out of the
#     partition named `production`, raw, at offset 0:
#         bootcmd           = ... run boot_sdmmc
#         boot_sdmmc        = run boot_production ; run boot_recovery
#         boot_production   = run sdmmc_read_production && bootm $loadaddr#$bootconf#$bootconf_sd#$bootconf_extra
#         sdmmc_read_production = part start mmc 0 production part_addr && part size mmc 0 production part_size && run mmc_read_vol
#         mmc_read_vol      = mmc read $loadaddr $part_addr 0x100 && imszb ... && test image_size -le part_size && ...
#         bootconf          = config-mt7988a-bananapi-bpi-r4-pro-4e
#         bootconf_sd       = mt7988a-bananapi-bpi-r4-pro-4e-sd
#         bootconf_extra    = mt7988a-bananapi-bpi-r4-pro-4e-iphy
#
#     (All of the above strings were read verbatim out of the vendor FIP blob in
#     the released OpenWrt SD image.)
#
# So the card MUST carry: a GPT with a `fip` entry (BL2), and a `production`
# partition large enough for the FIT (U-Boot).  The FIT itself is written raw
# at offset 0 of `production` and is produced separately by mk-sd-image.sh --
# disko cannot copy a file into a raw partition.
#
# Layout (identical geometry to the vendor GPT; those offsets are what BL2's
# own GPT scan and the BootROM expect):
#
#   #  name        start(sec)  size         type
#   1  bl2               34    8158  (~4M)  Linux
#   2  ubootenv        8192    1024  (512K) Linux
#   3  factory         9216    4096  (2M)   Linux
#   4  fip            13312    8192  (4M)   EFI    <- BL2 looks for this name
#   5  production    327680  917504 (448M)  Linux  <- U-Boot boots the FIT here
#   6  nixos-root   1245184   <fills>        Linux  btrfs root
#
# `start`/`end` are sectors with alignment 1: sgdisk's default 2048-sector
# alignment would round the firmware offsets and point BL2 at empty space.
#
# SAFETY: disko writes only the block device passed as `disk`; the board's
# SPI-NAND bootloader is never a target.  SD and eMMC share one mmc controller
# on MT7988, so pass a stable /dev/disk/by-id path from the live environment.
{
  assertions = [
    {
      assertion = !(builtins.elem disk [
        "/dev/mtdblock0"
        "/dev/mtdblock1"
        "/dev/mtdblock2"
        "/dev/mtdblock3"
        "/dev/mtd0"
        "/dev/mtd1"
        "/dev/mtd2"
        "/dev/mtd3"
      ]);
      message = ''
        disko target "${disk}" looks like raw SPI-NAND (the bootloader lives
        there). Refusing. Point --arg disk at the microSD.
      '';
    }
  ];

  disko.devices.disk.sdcard = {
    type = "disk";
    device = disk;
    content = {
      type = "gpt";
      partitions = {
        # --- firmware partitions (raw blobs, written by mk-sd-image.sh) ------
        # No filesystem: their content is the BL2/FIP payload the BootROM and
        # BL2 load.  They exist here so the GPT has the entries the firmware
        # looks up by name.
        bl2 = {
          name = "bl2";
          label = "bl2";
          start = "34";
          end = "8191";
          type = "8300";
          # `priority` controls disko's partition NUMBER (index).  Pin these to
          # the vendor GPT indices so a disko-created GPT is byte-for-byte
          # equivalent to mk-sd-image.sh's.  (The boot chain looks partitions up
          # by NAME, so this is not strictly required to boot -- but matching
          # the vendor layout means the two paths cannot drift.)
          priority = 1;
        };
        ubootenv = {
          name = "ubootenv";
          label = "ubootenv";
          start = "8192";
          end = "9215";
          type = "8300";
          priority = 2;
        };
        factory = {
          name = "factory";
          label = "factory";
          start = "9216";
          end = "13311";
          type = "8300";
          priority = 3;
        };
        fip = {
          name = "fip";
          label = "fip";
          start = "13312";
          end = "21503";
          type = "EF00";
          priority = 4;
        };

        # --- production: raw FIT the stock U-Boot boots ---------------------
        # Content is null (not formatted); mk-sd-image.sh writes the FIT raw at
        # offset 0.  Kept at the vendor's 448M so a kernel+initrd+dtb FIT fits
        # comfortably under U-Boot's `imszb`/part_size check.
        production = {
          name = "production";
          label = "production";
          start = "327680";
          end = "1245183";
          type = "8300";
          priority = 5;
        };

        # --- btrfs root ----------------------------------------------------
        root = {
          name = "nixos-root";
          label = "nixos-root";
          start = "1245184";
          size = "100%";
          # 100%-size partitions default to priority 9001 (created last); keep
          # that so nixos-root is partition 6 as in the vendor layout.
          priority = 6;
          content = {
            type = "btrfs";
            extraArgs = [ "-f" "-L" "nixos-root" ];
            subvolumes = {
              "/root" = {
                mountpoint = "/";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "/nix" = {
                mountpoint = "/nix";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "/persist" = {
                mountpoint = "/persist";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
            };
          };
        };
      };
    };
  };
}
