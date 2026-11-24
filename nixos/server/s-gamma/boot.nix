{ installDisk, ... }:

{
  fileSystems."/boot".neededForBoot = true;

  boot.loader.grub = {
    enable = true;
    device = installDisk;
    efiSupport = true;
    efiInstallAsRemovable = true;

    # /boot is 511M and this host auto-upgrades with allowReboot, so every new
    # kernel version adds a kernel + initrd pair. GRUB does NOT dedupe across
    # versions and there is no default limit (configurationLimit = 0 means
    # unlimited); generations that share a kernel version share the store path,
    # so the real growth is per unique kernel version, not per generation.
    #
    # Measured on 2026-11-24: bzImage ~12.96 MiB, initrd ~27.32 MiB, so ~40.3 MiB
    # per kernel version. Fixed /boot overhead (GRUB, fonts, EFI) is ~17 MiB.
    #   10 * 40.3 + 17 = ~420 MiB = ~82% of 511M
    # That leaves ~91 MiB headroom. Do not raise this without re-measuring: the
    # initrd grows whenever kernel modules or filesystem drivers are added, and a
    # full /boot makes `nixos-rebuild switch` fail half-way through an unattended
    # auto-upgrade. Lowering to 5 restores ~220 MiB of headroom if that happens.
    configurationLimit = 10;
  };
}
