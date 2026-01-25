{ config, lib, pkgs, ... }:

let
  mountPoint = "/persist-state";
  dev = "/dev/vdb";
in
{
  # Ensure mountpoint exists
  systemd.tmpfiles.rules = [
    "d ${mountPoint} 0755 root root -"
    "d ${mountPoint}/docker 0711 root root -"
  ];

  # Format once if empty, then mount. Runs on every switch.
  system.activationScripts.persistState = lib.stringAfter [ "etc" ] ''
    set -euo pipefail
    mkdir -p ${mountPoint}

    # If not formatted yet, format it.
    if ! ${pkgs.util-linux}/bin/blkid ${dev} >/dev/null 2>&1; then
      ${pkgs.e2fsprogs}/bin/mkfs.ext4 -F ${dev}
    fi

    # If not mounted yet, mount it.
    if ! ${pkgs.util-linux}/bin/findmnt -n ${mountPoint} >/dev/null 2>&1; then
      ${pkgs.util-linux}/bin/mount ${dev} ${mountPoint}
    fi
  '';

  # Bind mounts (will work once /persist-state is mounted)
  fileSystems."/var/lib/docker" = {
    device = "${mountPoint}/docker";
    fsType = "none";
    options = [ "bind" ];
  };

  virtualisation.docker.daemon.settings = {
    "data-root" = "/var/lib/docker";
    "storage-driver" = "overlay2";
  };
}

