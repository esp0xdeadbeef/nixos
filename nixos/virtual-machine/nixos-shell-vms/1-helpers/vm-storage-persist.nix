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
      "/var/lib/containers" = "/persist/vm-persists/${config.networking.hostName}/var/lib/containers";
    };
  };

  environment.etc."containers/storage.conf".text = ''
    [storage]
    driver = "vfs"
  '';
  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=755" ];
  };
}
