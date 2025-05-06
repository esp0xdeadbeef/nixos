{ config, pkgs, ... }:

{
  security.sudo = {
    enable = true;

    extraRules = [
      {
        users = [ "deadbeef" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/umount /home/deadbeef/.local/share/lxc/osep-lxc/rootfs/mnt";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/bindfs --uid-offset=100000 --gid-offset=100900 /home/deadbeef/github/osep/shared /home/deadbeef/.local/share/lxc/osep-lxc/rootfs/mnt";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/etc/nuke-lxc-from-orbit-on-shutdown.sh";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
