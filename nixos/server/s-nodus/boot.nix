{ config, lib, pkgs, ... }:

# Kernel, boot chain and console for the BPI-R4 Pro 4E (MT7988A).
#
# Boot chain -- this is the board's stock OpenWrt U-Boot's *built-in* env,
# read verbatim out of the vendor FIP blob:
#
#   cold power-on
#     -> MTK BootROM -> BL2 (SD sector 34)
#     -> BL2 reads the GPT and loads the ARM-TF FIP from the partition NAMED
#        "fip"  (if absent: "Partition 'fip' not found" -> "System halt!")
#     -> BL31 + BL33/U-Boot
#     -> bootcmd = if pstore check ; then run boot_recovery ; else run boot_sdmmc ; fi
#        boot_sdmmc = run boot_production ; run boot_recovery
#        boot_production = ... sdmmc_read_production && bootm $loadaddr#$bootconf#$bootconf_sd#$bootconf_extra
#        sdmmc_read_production: `part start mmc 0 production`, read the FIT raw
#          from offset 0 of that partition, `imszb` it, check size <= part_size
#     -> NixOS (console ttyS0)
#
# So the FIT lives in the `production` partition and is booted by the stock
# U-Boot; NixOS does NOT own the bootloader on this board (no systemd-boot,
# no EFI: the vendor U-Boot's default env contains no bootefi/BOOTAA64 path).
# The FIT is produced by ./fit.nix and written by mk-sd-image.sh.
let
  cfg = config.local.bpiR4Pro;
in
{
  options.local.bpiR4Pro = {
    enable = lib.mkEnableOption "Banana Pi BPI-R4 Pro 4E board support";
  };

  config = lib.mkIf cfg.enable {
    # --- kernel ---------------------------------------------------------
    # linuxPackages_latest on nixpkgs-unstable carries the official
    # mt7988a-bananapi-bpi-r4-pro-4e DTS (landed in Linux 6.19).  Board core
    # (MT7988A, mt7530 1G switch, 2.5G PHY, SD, I2C, RTC) is upstream; the
    # MaxLinear 10G switch, AS21010 10G PHYs and SFP+ muxes are not and stay
    # dark -- intentionally out of scope.
    boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

    # --- console / bootargs ---------------------------------------------
    # ttyS0 @ 115200 8N1 (confirmed on a live boot).
    #
    # clk_ignore_unused / pd_ignore_unused: keep "unused" clocks and power
    # domains on.  On MT7988 the MTK net drivers probe late; with
    # clk_disable_unused/genpd having gated their block a register access
    # hangs the CPU (rcu_sched stall -> hard LOCKUP -> boot wedge).  These
    # flags prevent that gating.
    #
    # NOTE: these go into the FIT's /chosen bootargs (fit.nix), because the
    # stock U-Boot uses the FIT's bootargs, not NixOS's boot.kernelParams.
    boot.kernelParams = lib.mkBefore [
      "console=ttyS0,115200n1"
      "clk_ignore_unused"
      "pd_ignore_unused"
    ];

    # --- bootloader -----------------------------------------------------
    # systemd-boot, chainloaded by the board's own U-Boot via `bootefi`.
    #
    # U-Boot's `boot_efi` loads a FAT EFI application from a fixed partition
    # and hands it a DTB:
    #
    #   boot_efi = load mmc 0:5 ... board.dtb && \
    #              load mmc 0:5 ... EFI/BOOT/BOOTAA64.EFI && \
    #              bootefi 0x46000000 0x47000000
    #
    # The ESP must therefore be GPT partition 5 of the disk U-Boot calls
    # `mmc 0` -- see ./disko.nix, which puts it first on the NVMe for exactly
    # this reason.  On this board the SD is mmc 0, so the ESP has to live on
    # the microSD, not the NVMe, for the stock env to find it.
    #
    # This replaces the old raw-FIT boot (`production` + a fixed `init=`).
    # With generations there is no store path pinned into the boot chain, so a
    # rebuild cannot leave the boot pointing at a toplevel absent from the
    # root -- which is the failure the FIT layout was prone to.
    boot.loader.grub.enable = lib.mkForce false;
    boot.loader.generic-extlinux-compatible.enable = lib.mkForce false;
    boot.loader.systemd-boot.enable = lib.mkForce true;
    boot.loader.efi.efiSysMountPoint = "/boot";
    # U-Boot has no persistent EFI variables, so bootctl must install to the
    # removable-media fallback path \EFI\BOOT\BOOTAA64.EFI, which U-Boot loads
    # directly.  Without this bootctl would create an EFI entry that nothing
    # can read.
    boot.loader.efi.canTouchEfiVariables = false;

    # U-Boot `bootefi` needs a DTB passed on its command line (fdtcontroladdr
    # is unset on this build), but systemd-boot stores each generation's dtb at
    # a hashed /EFI/nixos/ path that changes on every rebuild -- useless for a
    # stable U-Boot env.  Keep a stable copy at the ESP root for U-Boot, and
    # let systemd-boot override it per generation with the real one (its
    # `devicetree` loader-entry line).
    #
    # Absolute coreutils path: an on-board `nixos-rebuild` runs the bootloader
    # installer under systemd-run with a minimal PATH where bare `cp` is absent.
    boot.loader.systemd-boot.extraInstallCommands = ''
      ${pkgs.coreutils}/bin/cp -f \
        ${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name} \
        /boot/board.dtb
    '';
  };
}
