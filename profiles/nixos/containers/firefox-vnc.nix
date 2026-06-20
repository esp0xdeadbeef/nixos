{ config, lib, pkgs, ... }:
let
  cfg = config.local.containers.firefoxVnc;
  display = ":99";
  runtimeDirectory = "firefox-vnc";
  stateDirectory = "firefox-vnc";
  home = "/var/lib/${stateDirectory}";
  runtime = "/run/${runtimeDirectory}";
  profile = "${home}/profile";
in
{
  options.local.containers.firefoxVnc = {
    enable = lib.mkEnableOption "Firefox in a virtual X display exposed over VNC" // {
      default = true;
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address for x11vnc to listen on.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5900;
      description = "TCP port for the VNC server.";
    };

    width = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1280;
      description = "Virtual display width.";
    };

    height = lib.mkOption {
      type = lib.types.ints.positive;
      default = 720;
      description = "Virtual display height.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the VNC port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.firefox-vnc = {
      isSystemUser = true;
      group = "firefox-vnc";
      home = home;
      createHome = true;
    };
    users.groups.firefox-vnc = { };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.firefox-vnc = {
      description = "Firefox in a virtual X display exposed over VNC";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      path = with pkgs; [
        bash
        coreutils
        fluxbox
        procps
        x11vnc
        xdpyinfo
        xorg-server
      ];

      environment = {
        DISPLAY = display;
        HOME = home;
        MOZ_ENABLE_WAYLAND = "0";
        XDG_RUNTIME_DIR = runtime;
      };

      serviceConfig = {
        Type = "simple";
        User = "firefox-vnc";
        Group = "firefox-vnc";
        Restart = "always";
        RestartSec = "2s";
        StateDirectory = stateDirectory;
        RuntimeDirectory = runtimeDirectory;
        RuntimeDirectoryMode = "0700";
      };

      script = ''
        set -euo pipefail

        mkdir -p "${profile}"
        chmod 700 "${home}" "${profile}" "${runtime}"

        rm -f /tmp/.X99-lock
        Xvfb ${display} -screen 0 ${toString cfg.width}x${toString cfg.height}x24 -nolisten tcp &
        xvfb_pid="$!"

        cleanup() {
          kill "$firefox_pid" "$fluxbox_pid" "$xvfb_pid" 2>/dev/null || true
        }
        trap cleanup EXIT INT TERM

        for _ in $(seq 1 100); do
          if xdpyinfo -display ${display} >/dev/null 2>&1; then
            break
          fi
          sleep 0.1
        done

        fluxbox &
        fluxbox_pid="$!"

        ${pkgs.firefox}/bin/firefox \
          --no-remote \
          --new-instance \
          --profile "${profile}" \
          about:blank &
        firefox_pid="$!"

        exec x11vnc \
          -display ${display} \
          -listen ${lib.escapeShellArg cfg.listenAddress} \
          -rfbport ${toString cfg.port} \
          -forever \
          -shared \
          -nopw
      '';
    };
  };
}
