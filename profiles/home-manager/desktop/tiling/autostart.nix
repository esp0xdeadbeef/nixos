{ config, lib, pkgs, ... }:

let
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
  i3SpotifyEnabled = config.local.i3.spotify.enable;
  i3SpotifyCommand = config.local.i3.spotify.command;
  swaySpotifyEnabled = config.local.sway.spotify.enable;
  swaySpotifyCommand = config.local.sway.spotify.command;
  displayStartupCommand = config.local.i3.display.startupCommand;
in
{
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

  local.tiling.generated.i3.autostart = ''
    exec --no-startup-id ${pkgs.dex}/bin/dex --autostart --environment i3
    exec --no-startup-id ${pkgs.xset}/bin/xset s off -dpms
    exec --no-startup-id ${pkgs.xss-lock}/bin/xss-lock --transfer-sleep-lock -- ${pkgs.i3lock}/bin/i3lock -n -c 202020
    exec --no-startup-id ${pkgs.networkmanagerapplet}/bin/nm-applet
    exec_always --no-startup-id ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u "$USER" -f polkit-gnome-authentication-agent-1 >/dev/null || exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1'
    exec --no-startup-id ${pkgs.networkmanagerapplet}/bin/nm-applet
    exec --no-startup-id export XDG_SESSION_TYPE=x11
    exec --no-startup-id xsetroot -solid "#333333"
    exec --no-startup-id xsetroot -solid "#000000"
    exec --no-startup-id ${pkgs.picom}/bin/picom
    ${lib.optionalString (displayStartupCommand != null) "exec --no-startup-id ${displayStartupCommand}"}
    exec --no-startup-id ${pkgs.dunst}/bin/dunst
    exec --no-startup-id ${pkgs.numlockx}/bin/numlockx off
    exec_always --no-startup-id ${pkgs.bash}/bin/bash -c '${pkgs.procps}/bin/pkill -f "[.]autotiling-wrapped" || true; exec ${pkgs.autotiling}/bin/autotiling --splitratio 1.61'
    ${lib.optionalString i3SpotifyEnabled "exec_always --no-startup-id ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u \"$USER\" -x spotify >/dev/null || ${pkgs.procps}/bin/pgrep -u \"$USER\" -x spotify_player >/dev/null || exec ${i3SpotifyCommand}'"}
  '';

  local.tiling.generated.sway.autostart = ''
    exec ${pkgs.mako}/bin/mako
    exec ${pkgs.swayidle}/bin/swayidle -w before-sleep '${pkgs.swaylock}/bin/swaylock -f -c 202020'
    exec ${pkgs.networkmanagerapplet}/bin/nm-applet --indicator
    exec_always ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u "$USER" -f polkit-gnome-authentication-agent-1 >/dev/null || exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1'
    exec_always ${pkgs.bash}/bin/bash -c '${pkgs.procps}/bin/pkill -f "[.]autotiling-wrapped" || true; exec ${pkgs.autotiling}/bin/autotiling --splitratio 1.61'
    ${lib.optionalString swaySpotifyEnabled "exec_always ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u \"$USER\" -x spotify >/dev/null || ${pkgs.procps}/bin/pgrep -u \"$USER\" -x spotify_player >/dev/null || exec ${swaySpotifyCommand}'"}
  '';
}
