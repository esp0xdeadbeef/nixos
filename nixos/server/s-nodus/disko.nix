{
  # The microSD, named explicitly -- there is deliberately no usable default.
  # It is /dev/sda when preparing a card on a laptop but /dev/mmcblk0 on the
  # board, so any default would be wrong on one of the two and could point at
  # an unrelated disk.  Pass `--argstr disk <device>` (or `{ disk = ...; }`).
  #
  # null is allowed and only referenced when `withSdcard` is true, so the
  # NVMe-only configuration need not name a card at all.
  disk ? null
, rootDisk ? "/dev/nvme0n1"
  # Swap size in whole GiB, carved off the end of the root disk.
  #
  # The board has only 4 GiB of RAM, while evaluating the network pipeline peaks
  # around 3.3 GiB and heavier work (several concurrent evaluator/build
  # processes, VM images) spikes well past that.  64 GiB is 16x RAM, which keeps
  # even a large overshoot from turning into an OOM kill.  The cost is ~32 GiB
  # more reserved out of a ~954 GiB disk (root keeps ~889 GiB), so the headroom
  # is far more valuable than the space.
, swapSizeGiB ? 64
, withSdcard ? disk != null
  # Passed explicitly by callers; there is deliberately no `<nixpkgs>` fallback
  # because that is impure and breaks `nix flake check` / nixos-anywhere's pure
  # evaluation ("cannot look up '<nixpkgs/lib>' in pure evaluation mode").
, lib
, ...
}:

# s-nodus storage layout -- boot chain on microSD, root on NVMe.
#
# TWO devices, deliberately:
#
#   1. The microSD carries the *boot chain only* (bl2 / ubootenv / factory /
#      fip / production).  This is forced by the hardware: the MT7988 BootROM
#      loads BL2 from raw sector 34 of mmc 0, and BL2 then looks up the GPT
#      partition named `fip` on the same device.  Neither can move to NVMe
#      without reflashing the board's SPI-NAND firmware, which is never done.
#
#   2. The root filesystem lives on an NVMe SSD, because that is the part that
#      needs throughput and space.  A 30 GB SD card cannot hold the closure
#      once a QEMU VM is involved (~7.3 GiB), and its writeback path throttles
#      builds into `wbt_wait` stalls.
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
#   #  name        start(sec)  size         type        device
#   1  bl2               34    8158  (~4M)  Linux       SD
#   2  ubootenv        8192    1024  (512K) Linux       SD
#   3  factory         9216    4096  (2M)   Linux       SD
#   4  fip            13312    8192  (4M)   EFI         SD   <- BL2 looks for this name
#   5  production    327680  917504 (448M)  Linux       SD   <- U-Boot boots the FIT here
#   1  nixos-root      2048   <fills>        Linux       NVMe  btrfs root
#
# The SECOND NVMe is deliberately NOT described here: it is used only as
# throwaway swap while installing (the board needs more memory than its 4 GiB
# to evaluate this config), and holds nothing the machine depends on.
#
# `start`/`end` are sectors with alignment 1 on the SD: sgdisk's default
# 2048-sector alignment would round the firmware offsets and point BL2 at
# empty space.  The NVMe partition is normally aligned.
#
# SAFETY: disko writes only the block devices passed as `disk`/`rootDisk`; the
# board's SPI-NAND bootloader is never a target.
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

  # `root` is always present.  `sdcard` only when withSdcard is set: it is
  # /dev/sda when preparing a card on a laptop, but the board enumerates the
  # same card as /dev/mmcblk0, and installing the NVMe root must not touch it
  # at all (the boot chain lives there).
  #
  # Optional attributes rather than lib.mkIf: this file is evaluated both as a
  # disko configuration (a raw attrset, where mkIf has no meaning and silently
  # yields a `condition` key instead of the disk) and through the NixOS module
  # system.
  disko.devices.disk =
    {
      # --- root filesystem: Samsung SSD 960 PRO (NVMe) ---------------------
      #
      # The boot chain MUST stay on the microSD: the MT7988 BootROM loads BL2
      # from raw sector 34 of mmc 0, and BL2 then looks up the GPT partition
      # named `fip` on the same device.  Neither can be relocated to NVMe
      # without touching the board's SPI-NAND firmware, which is deliberately
      # never done.  Only the root moves, because that is the part that needs
      # speed and space.
      #
      # `root=fstab` is on the kernel cmdline, so stage-1 reads /etc/fstab to
      # find this; the PARTLABEL `nixos-root` below is what that entry resolves.
      root = {
        type = "disk";
        device = rootDisk;
        content = {
          type = "gpt";
          partitions = {
            root = {
              name = "nixos-root";
              label = "nixos-root";
              # 2048-aligned like any normal disk (nothing here is located by
              # raw offset, unlike the firmware partitions on the card).
              start = "2048";
              # Fills the disk.  There is no separate swap partition: swap is
              # a swapfile on /persist/swap (see the swapDevices comment in
              # default.nix), which costs no partitioning and can be resized
              # without re-laying-out the disk.
              size = "100%";
              priority = 1;
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
                  # Dedicated subvolume for the swapfile, deliberately excluded
                  # from services.btrfs.autoScrub: btrfs checksums every data
                  # block and a live swapfile is rewritten continuously, so
                  # scrubbing it reports a constant stream of checksum
                  # mismatches that look exactly like corruption.  `btrfs scrub`
                  # has no per-file skip, so a separate subvolume is the only
                  # supported way to leave it out.
                  "/swap" = {
                    mountpoint = "/persist/swap";
                    mountOptions = [ "compress=no" "noatime" ];
                  };
                };
              };
            };

          };
        };
      };
    }
    // lib.optionalAttrs withSdcard {
      # --- boot chain on the microSD ---------------------------------------
      #
      # Firmware partitions carry raw blobs and have no filesystem: their
      # content is the BL2/FIP payload the BootROM and BL2 load.  They exist
      # here so the GPT has the entries the firmware looks up by name.
      sdcard = {
        type = "disk";
        device = disk;
        content = {
          type = "gpt";
          partitions = {
            bl2 = {
              name = "bl2";
              label = "bl2";
              start = "34";
              end = "8191";
              type = "8300";
              # `priority` controls disko's partition NUMBER (index).  Pin these
              # to the vendor GPT indices so a disko-created GPT matches
              # mk-sd-image.sh's.  (The boot chain looks partitions up by NAME,
              # so this is not strictly required to boot -- but matching the
              # vendor layout means the two paths cannot drift.)
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

            # --- production: raw FIT the stock U-Boot boots -------------------
            #
            # U-Boot's env looks this partition up BY NAME and `bootm`s the FIT
            # written at offset 0:
            #
            #   boot_production       = run sdmmc_read_production && bootm $loadaddr#...
            #   sdmmc_read_production = part start mmc 0 production part_addr && ...
            #
            # Content is null (not formatted): the payload is a raw FIT, written
            # by mk-sd-image.sh.  Kept at the vendor's 448M so a kernel+initrd+
            # dtb FIT fits comfortably under U-Boot's imszb/part_size check.
            production = {
              name = "production";
              label = "production";
              start = "327680";
              end = "1245183";
              type = "8300";
              priority = 5;
            };

            # --- nixos-root: the STAGE-1 root filesystem, on the card ----------
            #
            # Deliberately on the microSD, not the NVMe.  The card holds a
            # complete NixOS (store closure, the system profile), so the board
            # boots a self-consistent system with no dependency on the SSD at
            # all.  That is what makes the SSD installable and, just as
            # importantly, recoverable: this root stays as the fallback if a
            # later move of the root to the NVMe goes wrong.
            #
            # A raw-FIT boot pins `init=` to /nix/var/nix/profiles/system/init,
            # which stage 1 resolves INSIDE THIS filesystem -- so the store and
            # the profile here can never disagree the way they did when the root
            # was written to the NVMe separately from the FIT.
            #
            # Sized to the disk rather than to the rootfs image: the extra space
            # is what holds the stage-1 swapfile and gives an on-board rebuild
            # somewhere to work.  Taking "100%" here is how the board previously
            # ended up with no usable swap.
            nixos-root = {
              name = "nixos-root";
              label = "nixos-root";
              start = "1245184";
              # 8 GiB, leaving the rest of the 29.7 GB card unallocated so the
              # root can be grown later without reflashing.
              end = "17727487";
              type = "8300";
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
                  # Dedicated subvolume for the swapfile, deliberately excluded
                  # from services.btrfs.autoScrub: btrfs checksums every data
                  # block and a live swapfile is rewritten continuously, so
                  # scrubbing it reports a constant stream of checksum
                  # mismatches that look exactly like corruption.  `btrfs scrub`
                  # has no per-file skip, so a separate subvolume is the only
                  # supported way to leave it out.
                  "/swap" = {
                    mountpoint = "/persist/swap";
                    mountOptions = [ "compress=no" "noatime" ];
                  };
                };
              };
            };
          };
        };
      };
    };
}
