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
  linesOption = description: lib.mkOption {
    type = lib.types.lines;
    default = "";
    inherit description;
  };
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

    extraConfig = linesOption "Additional lines appended to the generated ${name} config.";

    display.startupCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Display layout command to run when ${name} starts.";
    };

    spotify.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Spotify ${name} bindings and autostart.";
    };

    spotify.command = lib.mkOption {
      type = lib.types.str;
      default = spotifyCommand;
      description = "Command launched by the ${name} Spotify binding and autostart.";
    };
  };
  generatedOptions = wm: {
    autostart = linesOption "Generated ${wm} autostart commands.";
    keybindings = linesOption "Generated ${wm} keybindings.";
    windowRules = linesOption "Generated ${wm} window rules.";
    bar = linesOption "Generated ${wm} status bar config.";
  };
in
{
  options.local = {
    tilingManagerSettings.extraConfig = linesOption "Additional config appended to all generated tiling window-manager configs.";

    tilingManagerSettings.statusBarFont = lib.mkOption {
      type = lib.types.str;
      default = "pango:DejaVu Sans Mono, Font Awesome 6 Free Solid, Font Awesome 6 Free Regular, Font Awesome 6 Brands Regular, Noto Color Emoji 11";
      description = "Font used by generated tiling window-manager status bars.";
    };

    i3 = windowManagerOptions "i3" "i3bar";
    sway = windowManagerOptions "Sway" "swaybar";

    tiling.generated.i3 = generatedOptions "i3";
    tiling.generated.sway = generatedOptions "Sway";
  };
}
