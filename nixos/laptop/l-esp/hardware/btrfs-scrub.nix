{ pkgs, ... }:

let
  swapfile = "/persist/var/lib/swapfile";
in
{
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    priority = 100;
  };

  services.btrfs.autoScrub.enable = false;

  systemd.services.btrfs-scrub-with-swapoff = {
    description = "Scrub Btrfs after temporarily disabling the swapfile";
    unitConfig.RequiresMountsFor = [
      "/partition-root"
      swapfile
    ];
    serviceConfig = {
      Type = "oneshot";
      Nice = 10;
      IOSchedulingClass = "idle";
      TimeoutStopSec = "5min";
    };
    path = [
      pkgs.btrfs-progs
      pkgs.gnugrep
      pkgs.util-linux
    ];
    script = ''
      set -euo pipefail

      swap_was_active=0
      if swapon --show=NAME --noheadings | grep -Fxq '${swapfile}'; then
        swap_was_active=1
        swapoff '${swapfile}'
      fi

      restore_swap() {
        if [ "$swap_was_active" = 1 ]; then
          swapon '${swapfile}'
        fi
      }
      trap restore_swap EXIT

      btrfs scrub start -Bd /partition-root
    '';
  };

  systemd.timers.btrfs-scrub-with-swapoff = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "monthly";
      Persistent = true;
      RandomizedDelaySec = "6h";
    };
  };
}
