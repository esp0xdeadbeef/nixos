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
    # NixOS does NOT own the bootloader here: the board's vendor U-Boot boots
    # the FIT from the `production` partition directly, and its stock env has
    # no EFI/bootefi path.  Disable every NixOS bootloader so nothing writes
    # an ESP we do not use; generation management is via the FIT's root
    # (btrfs subvol + store paths) and mk-sd-image.sh.
    boot.loader.grub.enable = lib.mkForce false;
    boot.loader.generic-extlinux-compatible.enable = lib.mkForce false;
    boot.loader.systemd-boot.enable = lib.mkForce false;
    boot.loader.efi.canTouchEfiVariables = false; # no EFI vars on this board
  };
}
