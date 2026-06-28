{ inputs
, config
, pkgs
, lib
, ...
}:

{

  boot.initrd.systemd.tpm2.enable = true;
  systemd.tpm2.enable = true;
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
  boot.loader.systemd-boot.configurationLimit = 15;

  # # Force disable systemd-boot as Lanzaboote replaces it
  # boot.loader.systemd-boot.enable = lib.mkForce false;

  # Allow modifying EFI variables
  boot.loader.efi.canTouchEfiVariables = true;
  fileSystems."/boot".options = lib.mkForce [
    "fmask=0077"
    "dmask=0077"
  ];

  # allow nesting in vms:
  # boot.extraModprobeConfig = "options kvm_intel nested=1";

  # Initrd settings
  boot.initrd.systemd.enable = true;
  # boot.initrd.systemd.enableTpm2 = true;

}
