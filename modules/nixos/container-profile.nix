{ lib, ... }:

{
  # Containers do not boot
  boot.isContainer = true;

  # Disable all bootloader logic
  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.systemd-boot.enable = lib.mkForce false;

  # No initrd, no kernel
  boot.initrd.enable = false;

  # Containers do not define filesystems
  fileSystems = lib.mkForce {};

  # Silence assertions
  assertions = [];
}

