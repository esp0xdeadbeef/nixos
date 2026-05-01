{
  config,
  pkgs,
  lib,
  ...
}:
{
  boot.loader.grub.devices = [ "/dev/nvme0n1" ];
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.extraPerEntryConfig = lib.mkForce ''
    devicetree ($drive1)//dtbs/${config.hardware.deviceTree.kernelPackage.version}/${config.hardware.deviceTree.name}
  '';
  boot.loader.systemd-boot.configurationLimit = 10;
}
