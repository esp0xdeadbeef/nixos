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
    home=""
    display="''${DISPLAY:-}"
    xauthority="''${XAUTHORITY:-}"

    if [ -n "$display" ]; then
      uid="$(${pkgs.coreutils}/bin/id -u)"
      home="''${HOME:-}"
      if [ -z "$home" ]; then
        home="$(${pkgs.getent}/bin/getent passwd "$uid" | ${pkgs.coreutils}/bin/cut -d: -f6)"
      fi
      if [ -z "$xauthority" ] && [ -f "$home/.Xauthority" ]; then
        xauthority="$home/.Xauthority"
      fi
    fi

    if [ -z "$display" ] || [ -z "$xauthority" ]; then
      uid=""
      home=""

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
    fi

    export HOME="$home"
    export DISPLAY="$display"
    export XAUTHORITY="$xauthority"
    export XDG_RUNTIME_DIR="/run/user/$uid"

    runtime_home="$XDG_RUNTIME_DIR/xlayoutdisplay"
    ${pkgs.coreutils}/bin/mkdir -p "$runtime_home"

    config_file="$home/.xlayoutdisplay"
    if [ -f "$config_file" ]; then
      ${pkgs.coreutils}/bin/cp "$config_file" "$runtime_home/.xlayoutdisplay"
    else
      : > "$runtime_home/.xlayoutdisplay"
    fi

    ${lib.optionalString (cfg.maxResolution != null) ''
      ${pkgs.coreutils}/bin/printf 'max-resolution=%s\n' "${cfg.maxResolution}" >> "$runtime_home/.xlayoutdisplay"
    ''}

    export HOME="$runtime_home"
    export PATH="${lib.makeBinPath [ pkgs.xrandr pkgs.xrdb ]}:$PATH"

    snapshot_drm_connectors() {
      for connector in /sys/class/drm/card*-*; do
        [ -e "$connector/status" ] || continue

        name="''${connector##*/}"
        status="$(${pkgs.coreutils}/bin/cat "$connector/status" 2>/dev/null || true)"
        enabled="$(${pkgs.coreutils}/bin/cat "$connector/enabled" 2>/dev/null || true)"
        modes=0
        edid="none"

        if [ -f "$connector/modes" ]; then
          modes="$(${pkgs.coreutils}/bin/wc -l < "$connector/modes")"
        fi

        if [ -s "$connector/edid" ]; then
          edid="$(${pkgs.coreutils}/bin/sha256sum "$connector/edid" | ${pkgs.coreutils}/bin/cut -d ' ' -f 1)"
        fi

        ${pkgs.coreutils}/bin/printf '%s %s %s %s %s\n' "$name" "$status" "$enabled" "$modes" "$edid"
      done | ${pkgs.coreutils}/bin/sort
    }

    wait_for_stable_drm() {
      last=""
      stable=0
      deadline=$((SECONDS + ${toString cfg.stabilityTimeoutSeconds}))

      while [ "$SECONDS" -le "$deadline" ]; do
        ${pkgs.systemd}/bin/udevadm settle --timeout=3 || true
        current="$(snapshot_drm_connectors)"

        if [ "$current" = "$last" ] && [ -n "$current" ]; then
          stable=$((stable + 1))
        else
          stable=1
          last="$current"
        fi

        if [ "$stable" -ge ${toString cfg.stabilitySamples} ]; then
          return 0
        fi

        ${pkgs.coreutils}/bin/sleep ${toString cfg.stabilityIntervalSeconds}
      done

      echo "DRM display topology did not stabilize; skipping layout apply." >&2
      ${pkgs.coreutils}/bin/printf '%s\n' "$last" >&2
      return 1
    }

    wait_for_stable_drm || exit 0
    ${pkgs.xlayoutdisplay}/bin/xlayoutdisplay --noop -w 0 >/dev/null
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

    stabilitySamples = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "Number of identical DRM connector samples required before applying the layout.";
    };

    stabilityIntervalSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Seconds between DRM connector samples.";
    };

    stabilityTimeoutSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 20;
      description = "Maximum seconds to wait for a stable DRM connector topology before skipping the apply.";
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
    environment.systemPackages = [
      pkgs.xlayoutdisplay-selectors
    ];

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

    services.xserver.displayManager.sessionCommands = ''
      ${applyLayout} || true
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
