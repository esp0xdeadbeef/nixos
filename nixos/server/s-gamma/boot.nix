{ installDisk, ... }:

{
  fileSystems."/boot".neededForBoot = true;

  boot.loader.grub = {
    enable = true;
    device = installDisk;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
}
