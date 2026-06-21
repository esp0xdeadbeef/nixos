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

    ${lib.optionalString (cfg.maxExternalMode != null) ''
      safe_mode=${lib.escapeShellArg cfg.maxExternalMode}
      config_file=""
      xdg_config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
      for candidate in "$xdg_config_home/.xlayoutdisplay" "$HOME/.xlayoutdisplay" /etc/xlayoutdisplay; do
        [ -f "$candidate" ] || continue
        config_file="$candidate"
        break
      done

      if [ -n "$config_file" ]; then
        wait_seconds="$(${pkgs.gawk}/bin/awk -F= '$1 == "wait" { print $2; exit }' "$config_file")"
        [ -n "$wait_seconds" ] && ${pkgs.coreutils}/bin/sleep "$wait_seconds"
      else
        ${pkgs.coreutils}/bin/sleep ${toString cfg.waitSeconds}
      fi

      xrandr_query="$(${pkgs.xrandr}/bin/xrandr --query)"
      x_offset=0
      xrandr_args=()
      desired_state=""

      config_value() {
        [ -n "$config_file" ] || return 1
        ${pkgs.gawk}/bin/awk -F= -v key="$1" '$1 == key { print $2; exit }' "$config_file"
      }

      ordered_outputs() {
        if [ -n "$config_file" ]; then
          ${pkgs.gawk}/bin/awk -F= '$1 == "order" { print $2 }' "$config_file"
        fi
        printf '%s\n' "$xrandr_query" \
          | ${pkgs.gawk}/bin/awk '
              $2 == "connected" {
                position = "999999"
                for (i = 1; i <= NF; i++) {
                  if ($i ~ /^[0-9]+x[0-9]+\+/) {
                    split($i, geometry, "+")
                    position = geometry[2]
                    break
                  }
                }
                print position, $1
              }
            ' \
          | ${pkgs.coreutils}/bin/sort -n \
          | ${pkgs.gawk}/bin/awk '{ print $2 }'
      }

      output_mode() {
        printf '%s\n' "$xrandr_query" \
          | ${pkgs.gawk}/bin/awk -v output="$1" '
              $1 == output && $2 == "connected" {
                for (i = 1; i <= NF; i++) {
                  if ($i ~ /^[0-9]+x[0-9]+\+/) {
                    sub(/\+.*/, "", $i)
                    print $i
                    exit
                  }
                }
              }
            '
      }

      output_position() {
        printf '%s\n' "$xrandr_query" \
          | ${pkgs.gawk}/bin/awk -v output="$1" '
              $1 == output && $2 == "connected" {
                for (i = 1; i <= NF; i++) {
                  if ($i ~ /^[0-9]+x[0-9]+\+/) {
                    split($i, geometry, "+")
                    print geometry[2] "x" geometry[3]
                    exit
                  }
                }
              }
            '
      }

      output_has_mode() {
        printf '%s\n' "$xrandr_query" \
          | ${pkgs.gawk}/bin/awk -v output="$1" -v mode="$safe_mode" '
              $1 == output && $2 == "connected" { in_output = 1; next }
              $2 == "connected" { in_output = 0 }
              in_output && $1 == mode { found = 1 }
              END { exit found ? 0 : 1 }
            '
      }

      primary_output="$(config_value primary || true)"
      requested_rate="$(config_value rate || true)"
      requested_dpi="$(config_value dpi || true)"
      seen_outputs=" "

      while read -r output; do
        case "$seen_outputs" in
          *" $output "*) continue ;;
        esac
        seen_outputs="$seen_outputs$output "

        if ! printf '%s\n' "$xrandr_query" | ${pkgs.gawk}/bin/awk -v output="$output" '$1 == output && $2 == "connected" { found = 1 } END { exit found ? 0 : 1 }'; then
          continue
        fi

        mode="$(output_mode "$output")"
        case "$output" in
          eDP-* | LVDS-* | DSI-*)
            [ -n "$mode" ] || continue
            xrandr_args+=(--output "$output" --mode "$mode" --pos "''${x_offset}x0")
            if [ "$primary_output" = "$output" ]; then
              xrandr_args+=(--primary)
            fi
            desired_state="$desired_state$output:$mode:''${x_offset}x0:$([ "$primary_output" = "$output" ] && printf primary || true)"$'\n'
            x_offset=$((x_offset + ''${mode%x*}))
            ;;
          *)
            if output_has_mode "$output"; then
              xrandr_args+=(--output "$output" --mode "$safe_mode" --pos "''${x_offset}x0")
              desired_state="$desired_state$output:$safe_mode:''${x_offset}x0:"$'\n'
              x_offset=$((x_offset + ''${safe_mode%x*}))
            elif [ -n "$mode" ]; then
              xrandr_args+=(--output "$output" --mode "$mode" --pos "''${x_offset}x0")
              desired_state="$desired_state$output:$mode:''${x_offset}x0:"$'\n'
              x_offset=$((x_offset + ''${mode%x*}))
            fi
            ;;
        esac
      done < <(ordered_outputs)

      if [ "''${#xrandr_args[@]}" -gt 0 ]; then
        current_matches=1
        while IFS=: read -r output mode position primary_marker; do
          [ -n "$output" ] || continue
          [ "$(output_mode "$output")" = "$mode" ] || current_matches=0
          [ "$(output_position "$output")" = "$position" ] || current_matches=0
          if [ "$primary_marker" = primary ]; then
            printf '%s\n' "$xrandr_query" | ${pkgs.gawk}/bin/awk -v output="$output" '$1 == output && $0 ~ / connected primary / { found = 1 } END { exit found ? 0 : 1 }' || current_matches=0
          fi
        done <<< "$desired_state"

        if [ "$current_matches" = 1 ]; then
          echo "Display layout already matches capped policy; skipping xrandr." >&2
        else
          echo "Applying capped external display mode $safe_mode where available." >&2
          if [ -n "$requested_dpi" ]; then
            ${pkgs.xrandr}/bin/xrandr --dpi "$requested_dpi" "''${xrandr_args[@]}"
            echo "Xft.dpi: $requested_dpi" | ${pkgs.xrdb}/bin/xrdb -merge
          else
            ${pkgs.xrandr}/bin/xrandr "''${xrandr_args[@]}"
          fi
        fi
      fi
      exit 0
    ''}

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

    maxExternalMode = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "2560x1440";
      description = "Optional maximum mode to apply to connected non-laptop outputs after xlayoutdisplay.";
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
