{ config
, lib
, osConfig ? null
, pkgs
, ...
}:

let
  os = if osConfig == null then { } else osConfig;
  networkManagerEnabled = os.networking.networkmanager.enable or false;
  i3SpotifyEnabled = config.local.i3.spotify.enable;
  i3SpotifyCommand = config.local.i3.spotify.command;
  swaySpotifyEnabled = config.local.sway.spotify.enable;
  swaySpotifyCommand = config.local.sway.spotify.command;
  displayStartupCommand = config.local.i3.display.startupCommand;
  onePasswordGuiEnabled =
    (os.programs._1password-gui.enable or false)
    || hasPackage [
      "1password"
      "1password-gui"
    ];
  onePasswordGuiPackage = os.programs._1password-gui.package or pkgs._1password-gui;
  onePasswordCommand = "${onePasswordGuiPackage}/bin/1password --silent";
  onePasswordSwayCommand = "${pkgs.coreutils}/bin/env NIXOS_OZONE_WL=1 ${onePasswordCommand}";
  packageNames =
    let
      systemPackages = os.environment.systemPackages or [ ];
    in
    map lib.getName (systemPackages ++ (config.home.packages or [ ]));
  hasPackage = names: lib.any (name: lib.elem name packageNames) names;
  hasTeams = hasPackage [ "teams-for-linux" ];
  polkitAutostart = execAlways: ''
    ${execAlways} ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u "$USER" -f polkit-gnome-authentication-agent-1 >/dev/null || exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1'
  '';
  autotilingAutostart = execAlways: ''
    ${execAlways} ${pkgs.bash}/bin/bash -c '${pkgs.procps}/bin/pkill -f "[.]autotiling-wrapped" || true; exec ${pkgs.autotiling}/bin/autotiling --splitratio 1.61'
  '';
  spotifyAutostart = execAlways: command: ''
    ${execAlways} ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u "$USER" -x spotify >/dev/null || ${pkgs.procps}/bin/pgrep -u "$USER" -x spotify_player >/dev/null || exec ${command}'
  '';
  teamsAutostart = execAlways: ''
    ${execAlways} ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u "$USER" -x teams-for-linux >/dev/null || exec ${pkgs.teams-for-linux}/bin/teams-for-linux'
  '';
  onePasswordAutostart = execAlways: command: ''
    ${execAlways} ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u "$USER" -x 1password >/dev/null || ${pkgs.procps}/bin/pgrep -u "$USER" -x 1Password >/dev/null || exec ${command}'
  '';
in
{
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

  local.tiling.generated.i3.autostart = ''
    exec --no-startup-id ${pkgs.dex}/bin/dex --autostart --environment i3
    exec --no-startup-id ${pkgs.xset}/bin/xset s off -dpms
    ${polkitAutostart "exec_always --no-startup-id"}
    ${lib.optionalString networkManagerEnabled "exec --no-startup-id ${pkgs.networkmanagerapplet}/bin/nm-applet"}
    exec --no-startup-id export XDG_SESSION_TYPE=x11
    exec --no-startup-id xsetroot -solid "#333333"
    exec --no-startup-id ${pkgs.picom}/bin/picom
    ${lib.optionalString (displayStartupCommand != null) "exec --no-startup-id ${displayStartupCommand}"}
    exec --no-startup-id ${pkgs.dunst}/bin/dunst
    exec --no-startup-id ${pkgs.numlockx}/bin/numlockx off
    ${autotilingAutostart "exec_always --no-startup-id"}
    ${lib.optionalString onePasswordGuiEnabled (onePasswordAutostart "exec_always --no-startup-id" onePasswordCommand)}
    ${lib.optionalString i3SpotifyEnabled (spotifyAutostart "exec_always --no-startup-id" i3SpotifyCommand)}
    ${lib.optionalString hasTeams (teamsAutostart "exec_always --no-startup-id")}
  '';

  local.tiling.generated.sway.autostart = ''
    exec ${pkgs.mako}/bin/mako
    # Keep sleep/hibernate locking, but do not lock after an idle timeout.
    exec ${pkgs.swayidle}/bin/swayidle -w before-sleep '${pkgs.swaylock}/bin/swaylock -f -c 202020'
    ${lib.optionalString networkManagerEnabled "exec ${pkgs.networkmanagerapplet}/bin/nm-applet --indicator"}
    ${polkitAutostart "exec_always"}
    ${autotilingAutostart "exec_always"}
    ${lib.optionalString onePasswordGuiEnabled (onePasswordAutostart "exec_always" onePasswordSwayCommand)}
    ${lib.optionalString swaySpotifyEnabled (spotifyAutostart "exec_always" swaySpotifyCommand)}
    ${lib.optionalString hasTeams (teamsAutostart "exec_always")}
  '';
}
