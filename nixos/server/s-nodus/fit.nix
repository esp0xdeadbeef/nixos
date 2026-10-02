{ config, lib, pkgs, ... }:

# Build the NixOS **FIT image** (.itb) that the board's stock OpenWrt U-Boot
# boots directly.  This is the format its built-in env expects, verbatim from
# the vendor FIP blob:
#
#   boot_production       = ... bootm $loadaddr#$bootconf#$bootconf_sd#$bootconf_extra
#   bootconf              = config-mt7988a-bananapi-bpi-r4-pro-4e
#   bootconf_sd           = mt7988a-bananapi-bpi-r4-pro-4e-sd
#   bootconf_extra        = mt7988a-bananapi-bpi-r4-pro-4e-iphy
#   sdmmc_read_production = part start mmc 0 production part_addr && ... mmc_read_vol
#   mmc_read_vol          = mmc read $loadaddr $part_addr 0x100 && imszb ... && mmc read ...
#   loadaddr              = 0x50000000
#
# So U-Boot loads the whole FIT to 0x50000000, then `bootm`s the *default*
# configuration and applies the overlays named by $bootconf_sd/$bootconf_extra.
#
# IMPORTANT: `bootm` on a FIT address (not a filename) uses the FIT's DEFAULT
# configuration and applies the listed overlays.  Our configurations therefore
# must (a) have the same names U-Boot asks for, and (b) the base config must
# carry kernel + fdt + ramdisk, while the two overlay configs only carry fdt.
#
# The previous version of this file named the config
# `config-mt7988a-bananapi-bpi-r4-pro-4e` and provided NO `-sd`/`-iphy`
# overlay configs, and set a bootargs whose root= used PARTLABEL -- which the
# vendor U-Boot overrides with its own `root=/dev/fit0` semantics.  All three
# are fixed here.
let
  cfg = config.local.bpiR4Pro;

  # Our resolved board DTB (base + SD overlay), see ./dtb.nix.
  # hardware.deviceTree.name = "mediatek/mt7988a-...-sd.dtb", and dtbSource lays
  # it out as <dtbSource>/mediatek/...  -> join to the full path directly.
  dtb = config.hardware.deviceTree.package;
  dtbFile = "${dtb}/${config.hardware.deviceTree.name}";

  # The implicit device-tree overlays U-Boot asks for by these names.  They are
  # the *mainline* overlays shipped with the kernel source (the same ones
  # dtb.nix already compiles for the SD variant); we hand U-Boot pre-resolved
  # DTBs instead, and expose them under the names it requests so `bootm` with
  # $bootconf_sd/$bootconf_extra finds them.
  dtbSd = dtbFile;
  # The "iphy" overlay is out of scope (10G PHYs stay dark); map it to the same
  # resolved DTB so the requested config name exists and applies cleanly.
  dtbIphy = dtbFile;

  kernelImage = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
  initrd = "${config.system.build.initialRamdisk}/initrd";

  # Bootargs: U-Boot's stock env sets `root=/dev/fit0`, which does not exist
  # for NixOS.  Setting /chosen/bootargs in the FIT makes U-Boot use ours.
  #
  # `init=` is MANDATORY.  NixOS's systemd initrd stage-1 discovers the system
  # closure ONLY from the `init=` kernel parameter: initrd-find-nixos-closure
  # scans /proc/cmdline for `init=`, resolves it inside /sysroot, takes dirname
  # as the closure, and execs its `prepare-root`.  Without `init=` stage-1
  # prints "No init= parameter on the kernel command line" and the boot stalls
  # right after "Run /init as init process".  (This is why a bare
  # `root=.../init`-less cmdline fails even though the store contains the
  # closure.)
  #
  # `rootflags=subvol=/root` matches ./disko.nix's "/" subvolume; /nix and
  # /persist are separate subvolumes mounted from /etc/fstab.
  # clk/pd_ignore_unused are required (see boot.nix): without them the MTK net
  # driver's late probe hangs the CPU.
  # NOTE: this /chosen/bootargs is effectively advisory.  U-Boot's
  # image_setup_libfdt() always overwrites it with env_get("bootargs"), so the
  # real cmdline lives in the U-Boot env written by mk-sd-image.sh (from
  # uboot-env.txt).  We keep it here so the FIT is self-describing and so a
  # FIT booted from a stock/vendor env still has a sane cmdline.
  #
  # It must NOT pin init= to a specific toplevel: after an on-board rebuild the
  # env would still be correct (it uses the stable profile symlink) while this
  # would silently go stale.  Use the stable profile path for the same reason.
  bootargs = "console=ttyS0,115200n1 clk_ignore_unused pd_ignore_unused root=PARTLABEL=nixos-root rootflags=subvol=/root rootwait rw init=/nix/var/nix/profiles/system/init";

  itsFile = pkgs.writeText "bpi-r4-pro-4e.its" ''
    /dts-v1/;

    / {
      description = "NixOS for BPI-R4 Pro 4E";
      #address-cells = <1>;

      images {
        /* Addresses mirror the stock OpenWrt FIT (kernel 0x46000000, fdt
           0x45f00000): U-Boot loads the whole FIT at loadaddr=0x50000000 and
           then relocates these images, so they must not overlap that region. */
        kernel-1 {
          description = "NixOS ARM64 Linux";
          data = /incbin/("${kernelImage}");
          type = "kernel";
          arch = "arm64";
          os = "linux";
          compression = "none";
          load = <0x46000000>;
          entry = <0x46000000>;
          hash-1 { algo = "sha256"; };
        };

        fdt-1 {
          description = "BPI-R4 Pro 4E device tree";
          data = /incbin/("${dtbSd}");
          type = "flat_dt";
          arch = "arm64";
          compression = "none";
          load = <0x45f00000>;
          hash-1 { algo = "sha256"; };
        };

        /* The overlay configs U-Boot asks for by name ($bootconf_sd /
           $bootconf_extra).  We ship the already-resolved DTB under both so
           the requested configurations exist. */
        fdt-2 {
          description = "BPI-R4 Pro 4E SD (resolved)";
          data = /incbin/("${dtbSd}");
          type = "flat_dt";
          arch = "arm64";
          compression = "none";
          load = <0x45f00000>;
          hash-1 { algo = "sha256"; };
        };

        fdt-3 {
          description = "BPI-R4 Pro 4E iphy (resolved)";
          data = /incbin/("${dtbIphy}");
          type = "flat_dt";
          arch = "arm64";
          compression = "none";
          load = <0x45f00000>;
          hash-1 { algo = "sha256"; };
        };

        ramdisk-1 {
          description = "NixOS initrd";
          data = /incbin/("${initrd}");
          type = "ramdisk";
          arch = "arm64";
          os = "linux";
          compression = "none";
          load = <0x4a000000>;
          hash-1 { algo = "sha256"; };
        };
      };

      configurations {
        default = "config-mt7988a-bananapi-bpi-r4-pro-4e";

        /* Base config: U-Boot `bootm`s this one; it brings kernel+fdt+initrd. */
        config-mt7988a-bananapi-bpi-r4-pro-4e {
          description = "NixOS BPI-R4 Pro 4E";
          kernel = "kernel-1";
          fdt = "fdt-1";
          ramdisk = "ramdisk-1";
        };

        /* Overlay configs requested by $bootconf_sd / $bootconf_extra.
           `bootm <addr>#<cfg>#<sd>#<iphy>` applies these on top. */
        mt7988a-bananapi-bpi-r4-pro-4e-sd {
          description = "BPI-R4 Pro 4E SD overlay";
          fdt = "fdt-2";
        };

        mt7988a-bananapi-bpi-r4-pro-4e-iphy {
          description = "BPI-R4 Pro 4E iphy overlay";
          fdt = "fdt-3";
        };
      };

      /* Override U-Boot's own bootargs (stock env has root=/dev/fit0, which
         would make NixOS stage-1 wait forever -> watchdog reset -> loop). */
      chosen {
        bootargs = "${bootargs}";
      };
    };
  '';
in
{
  # Expose the FIT as a build artifact.  mkimage shells out to dtc to compile
  # the .its, so both ubootTools and dtc must be on PATH.
  system.build.bpiR4ProFit = pkgs.runCommand "nixos-bpi-r4-pro-4e.itb"
    {
      nativeBuildInputs = [ pkgs.ubootTools pkgs.dtc ];
    } ''
    mkimage -f ${itsFile} "$out"
  '';
}
