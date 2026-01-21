{
  lib,
  config,
  pkgs,
  ...
}:

{
  nixos-shell.mounts = {
    mountHome = false;
    extraMounts = {
      "/persist" = "/persist/vm-persists/${config.networking.hostName}";
    };
  };
}
