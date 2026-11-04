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
      path = with pkgs; [
        coreutils
        gnugrep
        iputils
      ];
      serviceConfig = {
        Type = "oneshot";
        PrivateTmp = true;
      };
      script = ''
        set -u

        dir=/persist/var/lib/internet-guard
        if ! mountpoint -q /persist; then
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
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = "systemctl start internet-guard.service || true";
    };
  };
}
