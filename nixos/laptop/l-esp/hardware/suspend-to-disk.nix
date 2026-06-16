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
}
