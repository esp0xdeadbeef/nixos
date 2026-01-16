{
  config,
  pkgs,
  lib,
  ...
}:
{

  #############################
  # Bootloader and Kernel Options
  #############################

  # Set systemd-boot configuration limit
  boot.loader.systemd-boot.configurationLimit = 15;

  # Force disable systemd-boot as Lanzaboote replaces it
  boot.loader.systemd-boot.enable = lib.mkForce false;

  # Allow modifying EFI variables
  boot.loader.efi.canTouchEfiVariables = true;

  # Lanzaboote configuration
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/persist/var/lib/sbctl";
  };
  # allow nesting in vms:
  boot.extraModprobeConfig = "options kvm_intel nested=1";

  # Initrd settings
  boot.initrd.systemd.enable = true;
  #boot.initrd.systemd.enableTpm2 = true;

  # System packages for Secure Boot debugging
  environment.systemPackages = with pkgs; [
    tpm2-tss
    sbctl
  ];

  # Filesystem optimizations
  fileSystems."/".options = [ "noatime" ];

  # Swap settings (commented out)
  #swapDevices = [ ];
}
