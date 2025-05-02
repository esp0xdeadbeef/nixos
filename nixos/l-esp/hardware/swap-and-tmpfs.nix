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
      size = 20 * 1024;
    }
  ];
  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
  };
}
