# s-nodus internet guard.
#
# s-nodus is headless: a wedged uplink leaves no console to recover from
# short of a power cycle. This guard probes two independent well-known
# targets and reboots ONLY when BOTH stay unreachable for the whole window.
# One reachable target means a DNS/CDN/routing problem, not a lost uplink,
# and must never trigger a reboot. Either target recovering resets the
# counter.
#
# The outage start time is persisted under /persist (impermanence keeps it
# across reboots); when /persist is not mounted it falls back to /run, which
# still counts correctly within a boot.
{ config, lib, pkgs, ... }:

let
  cfg = config.local.internetGuard;

  probeLine = target: ''
    if ${pkgs.iputils}/bin/ping -c1 -W5 -n ${target} > /dev/null 2>&1; then
      ok=1
    fi
  '';
in
{
  options.local.internetGuard = {
    enable = lib.mkEnableOption "reboot s-nodus when every internet probe target stays down for the window";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "*:0/5";
      description = "systemd OnCalendar expression controlling how often the probes run.";
    };

    windowSeconds = lib.mkOption {
      type = lib.types.int;
      default = 2 * 60 * 60;
      description = "How long all probe targets must keep failing before the host reboots.";
    };

    targets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "google.com" "nu.nl" ];
      description = "Independent probe targets; a reboot requires all of them to fail.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.internet-guard = {
      description = "Reboot when every internet probe target stays unreachable";
      # util-linux is required: the script uses `mountpoint` to decide whether
      # /persist is mounted. Without it the probe for /persist always fails and
      # the outage counter silently falls back to /run, losing the counter on
      # every reboot and breaking the "window survives a reboot" contract.
      #
      # systemd is required for the final `systemctl reboot`. It currently
      # resolves only because NixOS appends the implicit default service path;
      # declaring it keeps the one action that matters (rebooting a wedged
      # headless box) working if that default ever changes.
      path = with pkgs; [
        coreutils
        gnugrep
        iputils
        util-linux
        systemd
      ];
      serviceConfig = {
        Type = "oneshot";
        PrivateTmp = true;
      };
      script = ''
        set -u

        dir=/persist/var/lib/internet-guard
        # `command -v` keeps the dependency explicit: if util-linux ever drops
        # out of `path` again this is reported instead of silently counting in
        # /run and losing the window on the next reboot. The guard still runs:
        # on a headless box this reboot is the only recovery path, so degrading
        # to a volatile counter beats refusing to guard at all.
        if ! command -v mountpoint >/dev/null 2>&1; then
          say "mountpoint (util-linux) missing from PATH; outage counter will not survive a reboot"
        fi
        if ! mountpoint -q /persist 2>/dev/null; then
          dir=/run/internet-guard
        fi
        file=$dir/since
        mkdir -p "$dir"

        say() {
          printf '%s\n' "$1" | systemd-cat -t internet-guard || true
        }

        ok=0
        ${lib.concatMapStringsSep "\n" probeLine cfg.targets}

        if test "$ok" -eq 1; then
          if test -e "$file"; then
            say "internet reachable again; outage counter cleared"
            rm -f "$file"
          fi
          exit 0
        fi

        now=$(date +%s)
        if ! test -e "$file"; then
          printf '%s\n' "$now" >"$file"
          say "every probe target unreachable; outage counter started"
          exit 0
        fi

        since=$(cat "$file" 2>/dev/null || printf '%s' "$now")
        if ! printf '%s' "$since" | grep -qE '^[0-9]+$'; then
          printf '%s\n' "$now" >"$file"
          say "outage counter unreadable; restarting it"
          exit 0
        fi

        elapsed=$((now - since))
        if test "$elapsed" -lt ${toString cfg.windowSeconds}; then
          say "every probe target unreachable for $elapsed s; reboot at ${toString cfg.windowSeconds} s"
          exit 0
        fi

        say "every probe target unreachable for $elapsed s; rebooting"
        systemctl reboot
      '';
    };

    systemd.timers.internet-guard = {
      description = "Probe internet reachability for the s-nodus reboot guard";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Unit = "internet-guard.service";
        Persistent = false;
      };
    };

    # Probe once after boot so a boot with no uplink starts counting
    # immediately instead of waiting for the first calendar tick.
    systemd.services.internet-guard-boot = {
      description = "Initial internet guard probe";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # This unit shells out to `systemctl start`; declare the dependency
      # instead of relying on the implicit default service path.
      path = [
        pkgs.coreutils
        pkgs.systemd
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = "systemctl start internet-guard.service || true";
    };
  };
}
