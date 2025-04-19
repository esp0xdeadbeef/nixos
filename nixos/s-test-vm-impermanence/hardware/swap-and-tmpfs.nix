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
      device = "/var/lib/swapfile";
      size = 5 * 1024;
    }
  ];
  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
  };
}
