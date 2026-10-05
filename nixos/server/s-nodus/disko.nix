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
              # Ends `swapSizeGiB` before the end of the disk, leaving exactly
              # that much for the swap partition below.  Negative `end` is
              # disko's relative-to-disk form (see its example/swap.nix); a
              # computed expression like "100% - 64G" is rejected because
              # `size` only accepts the literal "100%" or an absolute size.
              end = "-${toString swapSizeGiB}G";
              # Before swap.
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
                };
              };
            };

            # --- swap -------------------------------------------------------
            #
            # A dedicated partition, not a swapfile: btrfs refuses a swapfile
            # unless it is created nocow via `btrfs filesystem mkswapfile`, and
            # a partition carries none of those constraints.
            #
            # This is what lets the GAMP pipeline be evaluated on the board at
            # all -- evaluation peaks near 3.3 GiB against only 4 GiB of RAM.
            swap = {
              name = "swap";
              label = "swap";
              # After root.
              priority = 2;
              # Starts `swapSizeGiB` before the end of the disk -- the mirror of
              # root's `end` -- and runs to the end.  Must NOT be a bare
              # "100%": disko would then place it first, whole-disk, and
              # overlap root.
              start = "-${toString swapSizeGiB}G";
              size = "100%";
              content = {
                type = "swap";
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

            # --- esp: systemd-boot + kernels + board dtb --------------------
            #
            # The board's OpenWrt U-Boot chainloads an EFI application with
            # `bootefi`:
            #
            #   boot_efi = load mmc 0:5 ... board.dtb && \
            #              load mmc 0:5 ... EFI/BOOT/BOOTAA64.EFI && \
            #              bootefi 0x46000000 0x47000000
            #
            # `mmc 0` is the microSD, and the vendor env addresses the ESP by
            # PARTITION NUMBER (5), so the ESP has to live *here*, not on the
            # NVMe -- U-Boot on this board has no `nvme` command to read a disk
            # by device (only PCI, which the Shell cannot easily use).
            #
            # U-Boot `bootefi`s the removable-media path \EFI\BOOT\BOOTAA64.EFI,
            # which `boot.loader.efi.canTouchEfiVariables = false` makes
            # systemd-boot install -- no EFI variables needed.
            #
            # Replaces the old raw-FIT `production` partition.  With boot
            # generations there is no store path pinned anywhere in the boot
            # chain, so a rebuild cannot leave the boot pointing at a toplevel
            # that is missing from the root -- which is how the FIT layout
            # broke.  Fixed geometry keeps the index at exactly 5; mk-sd-image.sh
            # writes bl2/ubootenv/factory/fip into partitions 1-4 and this ESP
            # is populated by `bootctl install` from the running system.
            esp = {
              name = "esp";
              label = "ESP";
              start = "1048576";
              end = "3145727"; # 1 GiB
              type = "EF00";
              priority = 5;
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
          };
        };
      };
    };
}
