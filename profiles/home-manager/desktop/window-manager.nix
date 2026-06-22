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
in

{
  options.local.i3 = {
    modifier = lib.mkOption {
      type = lib.types.str;
      default = "Mod4";
      description = "i3 modifier key.";
    };

    statusCommand = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.i3status}/bin/i3status";
      description = "Command used by i3bar for status output.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional lines appended to the generated i3 config.";
    };

    display.startupCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Display layout command to run when i3 starts.";
    };

    spotify.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Spotify i3 bindings and autostart.";
    };

    spotify.command = lib.mkOption {
      type = lib.types.str;
      default = spotifyCommand;
      description = "Command launched by the i3 Spotify binding and autostart.";
    };
  };
}
