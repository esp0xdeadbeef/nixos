{
  config,
  pkgs,
  lib,
  ...
}:
{

  boot.loader.systemd-boot.configurationLimit = 15;
}
