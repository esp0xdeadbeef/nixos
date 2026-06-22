{ lib, config, pkgs, ... }:
let
  cfg = config.local.laptop.xlayoutdisplayHotplug;
  primaryUser = config.local.users.primary.resolvedName;
  primaryHome = config.local.users.primary.homeDirectory;
  xlayoutdisplayConfig = pkgs.writeText "xlayoutdisplay-config" (
    lib.concatStringsSep "\n" cfg.configLines + "\n"
  );

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

    runtime_home="$XDG_RUNTIME_DIR/xlayoutdisplay"
    ${pkgs.coreutils}/bin/mkdir -p "$runtime_home"

    config_file="$home/.xlayoutdisplay"
    if [ -f "$config_file" ]; then
      ${pkgs.gnugrep}/bin/grep -v '^dpi=' "$config_file" > "$runtime_home/.xlayoutdisplay" || true
    else
      : > "$runtime_home/.xlayoutdisplay"
    fi

    dpi="$(
      ${pkgs.xrandr}/bin/xrandr --query \
        | ${pkgs.gawk}/bin/awk '
          function bucket(pixel_width, physical_dpi) {
            if (connected_count == 1 && physical_dpi > 0) {
              if (physical_dpi >= 240) {
                return 192
              } else if (physical_dpi >= 180) {
                return 168
              } else if (physical_dpi >= 150) {
                return 144
              } else if (physical_dpi >= 120) {
                return 120
              }

              return 96
            }

            if (pixel_width <= 1600) {
              return 96
            } else if (pixel_width <= 1920) {
              return 120
            } else if (pixel_width <= 2560) {
              return 132
            }

            return 144
          }

          function consider(line,    mode, mode_parts, width, mm, mm_parts, mm_width, physical_dpi) {
            if (line !~ / connected/) {
              return
            }
            if (line !~ /[0-9]+x[0-9]+\+/) {
              return
            }

            connected_count += 1

            match(line, /[0-9]+x[0-9]+\+/)
            mode = substr(line, RSTART, RLENGTH - 1)
            split(mode, mode_parts, "x")
            width = mode_parts[1] + 0

            if (min_width == "" || width < min_width) {
              min_width = width
            }

            if (line ~ /[0-9]+mm x [0-9]+mm/) {
              match(line, /[0-9]+mm x [0-9]+mm/)
              mm = substr(line, RSTART, RLENGTH)
              gsub(/mm/, "", mm)
              split(mm, mm_parts, " x ")
              mm_width = mm_parts[1] + 0
              if (mm_width > 0) {
                physical_dpi = width * 25.4 / mm_width
                if (max_physical_dpi == "" || physical_dpi > max_physical_dpi) {
                  max_physical_dpi = physical_dpi
                }
              }
            }
          }

          / connected/ {
            consider($0)
          }

          END {
            if (min_width == "") {
              exit
            }

            print bucket(min_width, max_physical_dpi)
          }
        '
    )"

    if [ -n "$dpi" ]; then
      ${pkgs.coreutils}/bin/printf 'dpi=%s\n' "$dpi" >> "$runtime_home/.xlayoutdisplay"
    fi
    ${lib.optionalString (cfg.maxResolution != null) ''
      ${pkgs.coreutils}/bin/printf 'max-resolution=%s\n' "${cfg.maxResolution}" >> "$runtime_home/.xlayoutdisplay"
    ''}

    export HOME="$runtime_home"
    export PATH="${lib.makeBinPath [ pkgs.xrandr pkgs.xrdb ]}:$PATH"

    ${pkgs.xlayoutdisplay}/bin/xlayoutdisplay -w ${toString cfg.waitSeconds}
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

    ${pkgs.systemd}/bin/udevadm monitor --kernel --udev \
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
      type = lib.types.ints.unsigned;
      default = 0;
      description = "Seconds passed to xlayoutdisplay -w on each attempt.";
    };

    debounceSeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 1;
      description = "Seconds to wait after the last hotplug event before applying the layout.";
    };

    maxResolution = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "2560x1440";
      description = "Maximum display mode xlayoutdisplay may choose.";
    };

    configLines = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "wait=2"
        "rate=60"
        "primary=eDP-1"
        "order=eDP-1"
      ];
      description = "Lines written to the primary user's .xlayoutdisplay file.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.configLines == [ ] || primaryUser != null && primaryHome != null;
        message = "local.laptop.xlayoutdisplayHotplug.configLines requires local.users.primary.name to resolve to a user.";
      }
    ];

    system.activationScripts.xlayoutdisplayConfig = lib.mkIf (cfg.configLines != [ ]) ''
      target="${primaryHome}/.xlayoutdisplay"
      tmp="$(${pkgs.coreutils}/bin/mktemp)"

      ${pkgs.coreutils}/bin/cat ${xlayoutdisplayConfig} > "$tmp"
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$target")"

      if [ -e "$target" ]; then
        ${pkgs.coreutils}/bin/cat "$tmp" > "$target"
      else
        ${pkgs.coreutils}/bin/install -m 0644 "$tmp" "$target"
      fi

      ${pkgs.coreutils}/bin/chown ${primaryUser}:users "$target"
      ${pkgs.coreutils}/bin/rm -f "$tmp"
    '';

    systemd.services.xlayoutdisplay-hotplug = {
      description = "Apply xlayoutdisplay after display hotplug";
      wantedBy = [ "graphical.target" ];
      after = [ "display-manager.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${monitorLayout}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
