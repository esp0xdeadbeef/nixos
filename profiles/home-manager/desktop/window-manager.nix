{ lib, pkgs, ... }:

let
  spotifyAvailable = lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.spotify;
  spotifyPlayerPersistent = pkgs.writeShellScriptBin "spotify-player-persistent" ''
    set -eu

    persist_home="/persist$HOME"
    config_args=()

    if [ -d "$persist_home/.config/spotify-player" ]; then
      config_args=(--config-folder "$persist_home/.config/spotify-player")
    fi

    exec ${pkgs.spotify-player}/bin/spotify_player "''${config_args[@]}" "$@"
  '';
  spotifyCommand =
    if spotifyAvailable then
      "${pkgs.spotify}/bin/spotify"
    else
      "${pkgs.alacritty}/bin/alacritty --title spotify-player -e ${spotifyPlayerPersistent}/bin/spotify-player-persistent";
  copyqStart = pkgs.writeShellScriptBin "copyq-start" ''
    set -eu

    copyq_config() {
      ${pkgs.coreutils}/bin/timeout 5s ${pkgs.copyq}/bin/copyq --start-server config "$@" >/dev/null 2>&1 || true
    }

    copyq_config maxitems 1000
    copyq_config expire_tab 0
    copyq_config save_delay_ms_on_item_added 1000
    copyq_config save_delay_ms_on_item_modified 1000
    copyq_config save_delay_ms_on_item_moved 1000
    copyq_config save_delay_ms_on_item_removed 1000
  '';
  windowManagerOptions = name: statusBar: {
    modifier = lib.mkOption {
      type = lib.types.str;
      default = "Mod4";
      description = "${name} modifier key.";
    };

    statusCommand = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.i3status}/bin/i3status";
      description = "Command used by ${statusBar} for status output.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional lines appended to the generated ${name} config.";
    };

    display.startupCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Display layout command to run when ${name} starts.";
    };

    spotify.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Spotify ${name} bindings and autostart.";
    };

    spotify.command = lib.mkOption {
      type = lib.types.str;
      default = spotifyCommand;
      description = "Command launched by the ${name} Spotify binding and autostart.";
    };
  };
in

{
  config = {
    home.packages = [
      pkgs.copyq
      copyqStart
    ];

    local.i3.extraConfig = lib.mkAfter ''
      exec --no-startup-id ${copyqStart}/bin/copyq-start
      bindsym $mod+Shift+v exec --no-startup-id ${pkgs.copyq}/bin/copyq show
    '';

    local.sway.extraConfig = lib.mkAfter ''
      exec ${copyqStart}/bin/copyq-start
      bindsym $mod+Shift+v exec ${pkgs.copyq}/bin/copyq show
    '';
  };

  options.local = {
    tilingManagerSettings.extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional config appended to all generated tiling window-manager configs.";
    };

    i3 = windowManagerOptions "i3" "i3bar";
    sway = windowManagerOptions "Sway" "swaybar";
  };
}
