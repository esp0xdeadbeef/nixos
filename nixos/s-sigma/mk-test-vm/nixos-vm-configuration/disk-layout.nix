{ lib, ... }:

{
  # Root filesystem
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # EFI system partition
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  # Partition layout for disk image builder
  boot.loader.efi.canTouchEfiVariables = false;

  # Tell make-disk-image how to partition the disk
  boot.loader.grub.enable = false;

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
  ];

  # Disk image specific layout
  system.build.partitionedDisk = lib.mkDefault {
    device = "/dev/vda";
    partitions = {
      ESP = {
        size = "512M";
        type = "EF00";
        filesystem = "vfat";
        label = "ESP";
        mountPoint = "/boot";
      };

      nixos = {
        size = "100%";
        filesystem = "ext4";
        label = "nixos";
        mountPoint = "/";
      };
    };
  };
}

