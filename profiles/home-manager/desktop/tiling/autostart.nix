{ config
, lib
, osConfig ? null
, pkgs
, ...
}:

let
  os = if osConfig == null then { } else osConfig;
  networkManagerEnabled = os.networking.networkmanager.enable or false;
  copyqConfigure = pkgs.writeShellScriptBin "copyq-configure" ''
    set -eu

    copyq_config_file="''${XDG_CONFIG_HOME:-$HOME/.config}/copyq/copyq.conf"
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$copyq_config_file")"

    copyq_config() {
      ${pkgs.crudini}/bin/crudini --set "$copyq_config_file" Options "$1" "$2"
    }

    copyq_config maxitems "1000"
    copyq_config expire_tab "0"
    copyq_config save_delay_ms_on_item_added "1000"
    copyq_config save_delay_ms_on_item_modified "1000"
    copyq_config save_delay_ms_on_item_moved "1000"
    copyq_config save_delay_ms_on_item_removed "1000"
    ${pkgs.crudini}/bin/crudini --set "$copyq_config_file" Plugins 'itemimage\image_editor' '${pkgs.ksnip}/bin/ksnip --edit %1'
  '';
  i3SpotifyEnabled = config.local.i3.spotify.enable;
  i3SpotifyCommand = config.local.i3.spotify.command;
  swaySpotifyEnabled = config.local.sway.spotify.enable;
  swaySpotifyCommand = config.local.sway.spotify.command;
  displayStartupCommand = config.local.i3.display.startupCommand;
  packageNames =
    let
      systemPackages = os.environment.systemPackages or [ ];
    in
    map lib.getName (systemPackages ++ (config.home.packages or [ ]));
  hasPackage = names: lib.any (name: lib.elem name packageNames) names;
  hasTeams = hasPackage [ "teams-for-linux" ];
in
{
  home.packages = [
    copyqConfigure
  ];

  services.copyq.enable = true;
  systemd.user.services.copyq.Service.ExecStartPre = "${copyqConfigure}/bin/copyq-configure";
  systemd.user.services.i3lock-before-sleep = {
    Unit = {
      Description = "Lock i3 before system sleep";
      Before = [ "sleep.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.i3lock}/bin/i3lock -c 202020";
    };

    Install.WantedBy = [ "sleep.target" ];
  };

  local.i3.extraConfig = lib.mkAfter ''
    bindsym $mod+Shift+v exec --no-startup-id ${pkgs.copyq}/bin/copyq show
  '';

  local.sway.extraConfig = lib.mkAfter ''
    bindsym $mod+Shift+v exec ${pkgs.copyq}/bin/copyq show
  '';

  local.tiling.generated.i3.autostart = ''
    exec --no-startup-id ${pkgs.dex}/bin/dex --autostart --environment i3
    exec --no-startup-id ${pkgs.xset}/bin/xset s off -dpms
    exec_always --no-startup-id ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u "$USER" -f polkit-gnome-authentication-agent-1 >/dev/null || exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1'
    ${lib.optionalString networkManagerEnabled "exec --no-startup-id ${pkgs.networkmanagerapplet}/bin/nm-applet"}
    exec --no-startup-id export XDG_SESSION_TYPE=x11
    exec --no-startup-id xsetroot -solid "#333333"
    exec --no-startup-id ${pkgs.picom}/bin/picom
    ${lib.optionalString (displayStartupCommand != null) "exec --no-startup-id ${displayStartupCommand}"}
    exec --no-startup-id ${pkgs.dunst}/bin/dunst
    exec --no-startup-id ${pkgs.numlockx}/bin/numlockx off
    exec_always --no-startup-id ${pkgs.bash}/bin/bash -c '${pkgs.procps}/bin/pkill -f "[.]autotiling-wrapped" || true; exec ${pkgs.autotiling}/bin/autotiling --splitratio 1.61'
    ${lib.optionalString i3SpotifyEnabled "exec_always --no-startup-id ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u \"$USER\" -x spotify >/dev/null || ${pkgs.procps}/bin/pgrep -u \"$USER\" -x spotify_player >/dev/null || exec ${i3SpotifyCommand}'"}
    ${lib.optionalString hasTeams "exec_always --no-startup-id ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u \"$USER\" -x teams-for-linux >/dev/null || exec ${pkgs.teams-for-linux}/bin/teams-for-linux'"}
  '';

  local.tiling.generated.sway.autostart = ''
    exec ${pkgs.mako}/bin/mako
    # Keep sleep/hibernate locking, but do not lock after an idle timeout.
    exec ${pkgs.swayidle}/bin/swayidle -w before-sleep '${pkgs.swaylock}/bin/swaylock -f -c 202020'
    ${lib.optionalString networkManagerEnabled "exec ${pkgs.networkmanagerapplet}/bin/nm-applet --indicator"}
    exec_always ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u "$USER" -f polkit-gnome-authentication-agent-1 >/dev/null || exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1'
    exec_always ${pkgs.bash}/bin/bash -c '${pkgs.procps}/bin/pkill -f "[.]autotiling-wrapped" || true; exec ${pkgs.autotiling}/bin/autotiling --splitratio 1.61'
    ${lib.optionalString swaySpotifyEnabled "exec_always ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u \"$USER\" -x spotify >/dev/null || ${pkgs.procps}/bin/pgrep -u \"$USER\" -x spotify_player >/dev/null || exec ${swaySpotifyCommand}'"}
    ${lib.optionalString hasTeams "exec_always ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u \"$USER\" -x teams-for-linux >/dev/null || exec ${pkgs.teams-for-linux}/bin/teams-for-linux'"}
  '';
}
