{ config, pkgs, ... }:

{
   security.sudo = {
    enable = true;

    # Grant 'deadbeef' passwordless sudo for exactly these two commands:
    extraRules = ''
      deadbeef ALL=(root) NOPASSWD: \
        /run/current-system/sw/bin/umount /home/deadbeef/.local/share/lxc/*/rootfs/mnt
      deadbeef ALL=(root) NOPASSWD: \
        /run/current-system/sw/bin/bindfs \
          --uid-offset=100000 --gid-offset=100900 \
          /home/deadbeef/github/osep/shared \
          /home/deadbeef/.local/share/lxc/osep-lxc/rootfs/mnt/
    '';
  };
}
