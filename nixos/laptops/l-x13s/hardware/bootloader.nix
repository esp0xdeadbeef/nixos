{
  config,
  pkgs,
  lib,
  ...
}:
{
  boot.loader.grub.devices = [ "/dev/nvme0n1" ];
  boot.loader.grub.efiSupport = true;
  boot.loader.systemd-boot.configurationLimit = 10;
}
