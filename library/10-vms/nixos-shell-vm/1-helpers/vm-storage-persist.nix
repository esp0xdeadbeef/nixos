{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.nixos-shell.nixosModules.nixos-shell
  ];

  nixos-shell.mounts = {
    mountHome = false;
    extraMounts = {
      "/persist" = "/persist/vm-persists/${config.networking.hostName}";
      # I need an option to cache those images, will try to make them persistent, without using p9 shares.
      #"/var/lib/containers" = "/persist/vm-persists/${config.networking.hostName}/var/lib/containers";
    };
  };

  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=755" ];
  };
}
