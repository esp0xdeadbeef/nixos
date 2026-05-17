{ pkgs, ... }:
let
  swapfile = "/persist/swap/swapfile";
in
{
  imports = [
    ./modules/host-composition.nix
  ];

  swapDevices = [
    {
      device = swapfile;
    }
  ];

  systemd.services.s-router-hetzner-persist-swapfile = {
    description = "Prepare persistent btrfs swapfile for Hetzner validation builds";
    before = [ "persist-swap-swapfile.swap" ];
    requiredBy = [ "persist-swap-swapfile.swap" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";
    path = [
      pkgs.btrfs-progs
      pkgs.coreutils
      pkgs.util-linux
    ];
    script = ''
      set -euo pipefail

      install -d -m 0700 /persist/swap
      if [ ! -e ${swapfile} ]; then
        btrfs filesystem mkswapfile --size 8g ${swapfile}
      fi
      chmod 0600 ${swapfile}
    '';
  };
}
