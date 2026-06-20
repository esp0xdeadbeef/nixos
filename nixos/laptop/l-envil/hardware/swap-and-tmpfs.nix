{ config
, lib
, pkgs
, modulesPath
, ...
}:
{
  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
  };
}
