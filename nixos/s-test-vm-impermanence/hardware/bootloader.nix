{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:

{

  boot.initrd.systemd.tpm2.enable = true;
  # boot.initrd.luks.devices.root = {
  #   device = "/dev/disk/by-partuuid/c5c3e4e1-f22d-429f-b3a2-50775c673279";
  # };
  # security.tpm2.enable = true;

  #   fileSystems."/" = {
  #     device = "/dev/root_vg/root";
  #     fsType = "btrfs";
  #     options = [ "subvol=root" ];
  # };
  # Set systemd-boot configuration limit
  boot.loader.systemd-boot.configurationLimit = 2;

  # # Force disable systemd-boot as Lanzaboote replaces it
  # boot.loader.systemd-boot.enable = lib.mkForce false;

  # Allow modifying EFI variables
  boot.loader.efi.canTouchEfiVariables = true;

  # allow nesting in vms:
  # boot.extraModprobeConfig = "options kvm_intel nested=1";

  # Initrd settings
  boot.initrd.systemd.enable = true;
  # boot.initrd.systemd.enableTpm2 = true;

  
}
