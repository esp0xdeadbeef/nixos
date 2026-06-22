{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  swapDevices = [
    {
      device = "/persist/var/lib/swapfile";
      size = 45 * 1024;
    }
  ];

  # findmnt -no SOURCE,FSTYPE,UUID /persist
  boot.resumeDevice = "/dev/disk/by-uuid/016f1050-7553-42ee-9fe2-8575b4b3c754";

  # sudo btrfs inspect-internal map-swapfile -r /persist/var/lib/swapfile
  boot.kernelParams = [
    "resume_offset=13769397"
  ];

  # This driver only exposes DDR5 SPD temperature sensors on this laptop, and
  # currently fails noisily during suspend/hibernate restore:
  # spd5118_resume [spd5118] returns -6.
  boot.blacklistedKernelModules = [ "spd5118" ];

}
