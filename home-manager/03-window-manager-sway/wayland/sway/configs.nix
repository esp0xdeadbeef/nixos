{ config, lib, pkgs, ... }:

let
  modifier = config.local.sway.modifier;
  statusCommand = config.local.sway.statusCommand;
  editScreenshot = pkgs.writeShellScriptBin "sway-edit-screenshot" ''
    set -eu

    dir="$HOME/Pictures/Screenshots"
    mkdir -p "$dir"
    file="$dir/screenshot-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S).png"

    ${pkgs.sway-contrib.grimshot}/bin/grimshot save anything - \
      | ${pkgs.swappy}/bin/swappy -f - -o "$file"

    ${pkgs.wl-clipboard}/bin/wl-copy < "$file"
  '';
  extraConfig = ''
    ${config.local.sway.extraConfig}
    ${config.local.tilingManagerSettings.extraConfig}
  '';
  spotifyEnabled = config.local.sway.spotify.enable;
  spotifyCommand = config.local.sway.spotify.command;
in
{
  home.packages = with pkgs; [
    alacritty
    autotiling
    brightnessctl
    grim
    mako
    networkmanagerapplet
    pamixer
    pavucontrol
    polkit_gnome
    rofi
    slurp
    sway
    sway-contrib.grimshot
    swayidle
    swaylock
    swappy
    wl-clipboard
    wofi
  ];

  # Sway Configuration
  home.file.".config/sway/config".text = ''
    set $mod ${modifier}

    font pango:monospace 10
    floating_modifier $mod
    focus_follows_mouse no
    gaps inner 2
    gaps outer 2
    smart_gaps on

    exec ${pkgs.mako}/bin/mako
    exec ${pkgs.swayidle}/bin/swayidle -w before-sleep '${pkgs.swaylock}/bin/swaylock -f -c 202020'
    exec ${pkgs.networkmanagerapplet}/bin/nm-applet --indicator
    exec_always ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u "$USER" -f polkit-gnome-authentication-agent-1 >/dev/null || exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1'
    exec_always ${pkgs.bash}/bin/bash -c '${pkgs.procps}/bin/pkill -f "[.]autotiling-wrapped" || true; exec ${pkgs.autotiling}/bin/autotiling --splitratio 1.61'
    ${lib.optionalString spotifyEnabled "exec_always ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u \"$USER\" -x spotify >/dev/null || ${pkgs.procps}/bin/pgrep -u \"$USER\" -x spotify_player >/dev/null || exec ${spotifyCommand}'"}

    bindsym $mod+Return exec ${pkgs.alacritty}/bin/alacritty
    bindsym $mod+q kill
    bindsym $mod+d exec ${pkgs.rofi}/bin/rofi -modi drun\,run -show drun
    bindsym $mod+Shift+d exec ${pkgs.rofi}/bin/rofi -show window
    ${lib.optionalString spotifyEnabled "bindsym $mod+F3 exec ${spotifyCommand}"}

    bindsym $mod+j focus left
    bindsym $mod+k focus down
    bindsym $mod+l focus up
    bindsym $mod+semicolon focus right
    bindsym $mod+Left focus left
    bindsym $mod+Down focus down
    bindsym $mod+Up focus up
    bindsym $mod+Right focus right

    bindsym $mod+Shift+j move left
    bindsym $mod+Shift+k move down
    bindsym $mod+Shift+l move up
    bindsym $mod+Shift+semicolon move right
    bindsym $mod+Shift+Left move left
    bindsym $mod+Shift+Down move down
    bindsym $mod+Shift+Up move up
    bindsym $mod+Shift+Right move right

    bindsym $mod+h split h
    bindsym $mod+v split v
    bindsym $mod+f fullscreen toggle
    bindsym $mod+s layout stacking
    bindsym $mod+w layout tabbed
    bindsym $mod+e layout toggle split

    bindsym $mod+Shift+space floating toggle
    bindsym $mod+space focus mode_toggle
    bindsym $mod+a focus parent

    set $ws1 "1"
    set $ws2 "2"
    set $ws3 "3"
    set $ws4 "4"
    set $ws5 "5"
    set $ws6 "6"
    set $ws7 "7"
    set $ws8 "8"
    set $ws9 "9"
    set $ws10 "10"

    bindsym $mod+1 workspace number $ws1
    bindsym $mod+2 workspace number $ws2
    bindsym $mod+3 workspace number $ws3
    bindsym $mod+4 workspace number $ws4
    bindsym $mod+5 workspace number $ws5
    bindsym $mod+6 workspace number $ws6
    bindsym $mod+7 workspace number $ws7
    bindsym $mod+8 workspace number $ws8
    bindsym $mod+9 workspace number $ws9
    bindsym $mod+0 workspace number $ws10

    bindsym $mod+Shift+1 move container to workspace number $ws1
    bindsym $mod+Shift+2 move container to workspace number $ws2
    bindsym $mod+Shift+3 move container to workspace number $ws3
    bindsym $mod+Shift+4 move container to workspace number $ws4
    bindsym $mod+Shift+5 move container to workspace number $ws5
    bindsym $mod+Shift+6 move container to workspace number $ws6
    bindsym $mod+Shift+7 move container to workspace number $ws7
    bindsym $mod+Shift+8 move container to workspace number $ws8
    bindsym $mod+Shift+9 move container to workspace number $ws9
    bindsym $mod+Shift+0 move container to workspace number $ws10

    bindsym $mod+Shift+c reload
    bindsym $mod+Shift+r reload
    bindsym $mod+Shift+e exec ${pkgs.sway}/bin/swaymsg exit
    bindsym $mod+Escape exec ${pkgs.swaylock}/bin/swaylock -f -c 202020
    bindsym $mod+Print+Shift exec ${editScreenshot}/bin/sway-edit-screenshot
    bindsym $mod+comma move workspace to output left
    bindsym $mod+period move workspace to output right
    bindsym $mod+bracketright exec ${pkgs.pamixer}/bin/pamixer --increase 10
    bindsym $mod+bracketleft exec ${pkgs.pamixer}/bin/pamixer --decrease 10

    for_window [class="google-chrome" class="Google-chrome"] move window to workspace 2
    for_window [class="Chromium" title=".*"] move container to workspace 2
    for_window [class="Spotify"] move to workspace 4
    for_window [title="spotify-player"] move to workspace 4
    for_window [class="X2GoAgent"] move window to workspace 7
    for_window [class="Navigator" class="firefox"] move window to workspace 8
    for_window [class="Firefox"] move window to workspace 8
    for_window [class="firefox"] move window to workspace 8
    for_window [class="dropbox"] move window to workspace 10
    for_window [class="Dropbox"] move window to workspace 10
    for_window [class="Maestral"] move window to workspace 10
    for_window [class="maestral"] move window to workspace 10

    mode "resize" {
      bindsym j resize shrink width 10 px
      bindsym k resize grow height 10 px
      bindsym l resize shrink height 10 px
      bindsym semicolon resize grow width 10 px
      bindsym Left resize shrink width 10 px
      bindsym Down resize grow height 10 px
      bindsym Up resize shrink height 10 px
      bindsym Right resize grow width 10 px
      bindsym Return mode "default"
      bindsym Escape mode "default"
      bindsym $mod+r mode "default"
    }
    bindsym $mod+t mode "resize"

    bar {
      status_command ${statusCommand}
      position bottom
      modifier $mod
      workspace_min_width 40
      colors {
        separator #282a36
        background #282a3670
        statusline #f8f8f2
        focused_workspace #50fa7b70 #50fa7b #282a36
        active_workspace #8be9fd70 #8be9fd #282a36
        inactive_workspace #282a3670 #282a3670 #f8f8f2
        urgent_workspace #2f343a70 #ff555570 #282a36
      }
    }

    ${extraConfig}
  '';
}
