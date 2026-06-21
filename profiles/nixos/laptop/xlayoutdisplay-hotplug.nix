{ lib, config, pkgs, ... }:
let
  cfg = config.local.laptop.xlayoutdisplayHotplug;

  applyLayout = pkgs.writeShellScript "xlayoutdisplay-apply" ''
    set -eu

    uid=""

    while read -r session _; do
      [ "$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Type --value)" = "x11" ] || continue
      [ "$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Active --value)" = "yes" ] || continue

      uid="$(${pkgs.systemd}/bin/loginctl show-session "$session" -p User --value)"
      break
    done < <(${pkgs.systemd}/bin/loginctl list-sessions --no-legend)

    if [ -z "$uid" ]; then
      echo "No active X11 session found; skipping display layout." >&2
      exit 0
    fi

    home="$(${pkgs.getent}/bin/getent passwd "$uid" | ${pkgs.coreutils}/bin/cut -d: -f6)"
    if [ -z "$home" ]; then
      echo "No home directory found for uid $uid; skipping display layout." >&2
      exit 0
    fi

    display=""
    for socket in /tmp/.X11-unix/X*; do
      [ -S "$socket" ] || continue
      [ "$(${pkgs.coreutils}/bin/stat -c %u "$socket")" = "$uid" ] || continue
      display=":''${socket##*/X}"
      break
    done

    if [ -z "$display" ]; then
      echo "No X11 socket found for uid $uid; skipping display layout." >&2
      exit 0
    fi

    xauthority=""
    for pid in $(${pkgs.procps}/bin/pgrep -x Xorg || true); do
      [ "$(${pkgs.coreutils}/bin/stat -c %u "/proc/$pid")" = "$uid" ] || continue

      xauthority="$(
        ${pkgs.coreutils}/bin/tr '\0' '\n' < "/proc/$pid/cmdline" \
          | ${pkgs.gawk}/bin/awk 'prev { print; exit } $0 == "-auth" { prev = 1 }'
      )"
      [ -n "$xauthority" ] && break
    done

    if [ -z "$xauthority" ]; then
      echo "No Xauthority path found for uid $uid; skipping display layout." >&2
      exit 0
    fi

    export HOME="$home"
    export DISPLAY="$display"
    export XAUTHORITY="$xauthority"
    export XDG_RUNTIME_DIR="/run/user/$uid"

    exec ${pkgs.xlayoutdisplay}/bin/xlayoutdisplay -w ${toString cfg.waitSeconds}
  '';

  monitorLayout = pkgs.writeShellScript "xlayoutdisplay-hotplug-monitor" ''
    set -eu

    pending_apply=""

    schedule_apply() {
      if [ -n "$pending_apply" ] && ${pkgs.procps}/bin/kill -0 "$pending_apply" 2>/dev/null; then
        ${pkgs.procps}/bin/kill "$pending_apply" 2>/dev/null || true
        wait "$pending_apply" 2>/dev/null || true
      fi

      (
        ${pkgs.coreutils}/bin/sleep ${toString cfg.debounceSeconds}
        ${applyLayout} || true
      ) &
      pending_apply="$!"
    }

    trap 'if [ -n "$pending_apply" ]; then ${pkgs.procps}/bin/kill "$pending_apply" 2>/dev/null || true; fi' EXIT

    ${applyLayout} || true

    ${pkgs.systemd}/bin/udevadm monitor --kernel --udev ${lib.concatMapStringsSep " " (subsystem: "--subsystem-match=${lib.escapeShellArg subsystem}") cfg.subsystems} \
      | while read -r line; do
          case "$line" in
            KERNEL* | UDEV*) schedule_apply ;;
          esac
        done
  '';
in
{
  options.local.laptop.xlayoutdisplayHotplug = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.services.xserver.windowManager.i3.enable;
      description = "Whether to run the xlayoutdisplay hotplug monitor.";
    };

    waitSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Seconds passed to xlayoutdisplay -w before applying the layout.";
    };

    debounceSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "Seconds to wait after the last hotplug event before applying the layout.";
    };

    subsystems = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "drm"
        "usb"
      ];
      description = "udevadm subsystems that should trigger xlayoutdisplay reconciliation.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.xlayoutdisplay-hotplug = {
      description = "Apply xlayoutdisplay after display hotplug";
      wantedBy = [ "graphical.target" ];
      after = [ "display-manager.service" ];
      path = [
        pkgs.xrandr
        pkgs.xrdb
      ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${monitorLayout}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
