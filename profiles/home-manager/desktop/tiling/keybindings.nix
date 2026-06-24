{ config, lib, pkgs, ... }:

let
  thunar = pkgs.thunar or pkgs.xfce.thunar;
  i3Modifier = config.local.i3.modifier;
  i3SpotifyEnabled = config.local.i3.spotify.enable;
  i3SpotifyCommand = config.local.i3.spotify.command;
  swaySpotifyEnabled = config.local.sway.spotify.enable;
  swaySpotifyCommand = config.local.sway.spotify.command;
  packageNames = map lib.getName (config.home.packages or [ ]);
  hasPackage = names: lib.any (name: lib.elem name packageNames) names;
  hasTeams = hasPackage [ "teams-for-linux" ];
  editScreenshot = pkgs.writeShellScriptBin "sway-edit-screenshot" ''
    set -eu

    dir="$HOME/Pictures/Screenshots"
    mkdir -p "$dir"
    file="$dir/screenshot-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S).png"

    ${pkgs.sway-contrib.grimshot}/bin/grimshot save anything - \
      | ${pkgs.swappy}/bin/swappy -f - -o "$file"

    ${pkgs.wl-clipboard}/bin/wl-copy < "$file"
  '';
  audioKeybindings = execPrefix: ''
    bindsym XF86AudioRaiseVolume ${execPrefix} ${pkgs.pamixer}/bin/pamixer --increase 10
    bindsym XF86AudioLowerVolume ${execPrefix} ${pkgs.pamixer}/bin/pamixer --decrease 10
    bindsym XF86AudioMute ${execPrefix} ${pkgs.pamixer}/bin/pamixer --toggle-mute
    bindsym XF86AudioMicMute ${execPrefix} ${pkgs.pamixer}/bin/pamixer --default-source --toggle-mute
    bindsym XF86AudioPlay ${execPrefix} ${pkgs.playerctl}/bin/playerctl play-pause
    bindsym XF86AudioPause ${execPrefix} ${pkgs.playerctl}/bin/playerctl play-pause
    bindsym XF86AudioStop ${execPrefix} ${pkgs.playerctl}/bin/playerctl stop
    bindsym XF86AudioNext ${execPrefix} ${pkgs.playerctl}/bin/playerctl next
    bindsym XF86AudioPrev ${execPrefix} ${pkgs.playerctl}/bin/playerctl previous
  '';
  brightnessKeybindings = execPrefix: ''
    bindsym XF86MonBrightnessUp ${execPrefix} "${pkgs.brightnessctl}/bin/brightnessctl set +10%"
    bindsym XF86MonBrightnessDown ${execPrefix} "${pkgs.brightnessctl}/bin/brightnessctl set 10%-"
  '';
in
{
  local.tiling.generated.i3.keybindings = ''
    ${audioKeybindings "exec --no-startup-id"}
    ${brightnessKeybindings "exec --no-startup-id"}

    bindsym $mod+Return exec ${pkgs.alacritty}/bin/alacritty
    bindsym $mod+q kill
    bindsym $mod+d exec --no-startup-id "${pkgs.rofi}/bin/rofi -modi drun,run -show drun"
    bindsym $mod+Shift+d exec --no-startup-id "${pkgs.rofi}/bin/rofi -show window"
    ${lib.optionalString hasTeams "bindsym $mod+F2 exec --no-startup-id ${pkgs.teams-for-linux}/bin/teams-for-linux"}

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
    bindsym $mod+Shift+r restart
    bindsym $mod+Shift+x exec ${pkgs.betterlockscreen}/bin/betterlockscreen -l dimblur
    bindsym $mod+Shift+e exec "${pkgs.i3}/bin/i3-nagbar -t warning -m 'You pressed the exit shortcut. Do you really want to exit i3? This will end your X session.' -B 'Yes, exit i3' '${pkgs.i3}/bin/i3-msg exit ; ${pkgs.procps}/bin/pkill X ; ${pkgs.procps}/bin/pkill xfce4-session'"
    bindsym $mod+t mode "resize"
    bindsym $mod+m mode "exit: [l]ogout, [r]eboot, [s]hutdown"
    bindsym $mod+i exec ${thunar}/bin/thunar
    bindsym $mod+Escape exec ${pkgs.i3lock}/bin/i3lock -n -c 202020
    bindsym $mod+c exec google-chrome-stable
    ${lib.optionalString i3SpotifyEnabled "bindsym $mod+F3 exec ${i3SpotifyCommand}"}
    bindsym Print exec "${pkgs.flameshot}/bin/flameshot gui"
    bindsym $mod+Print exec "${pkgs.ksnip}/bin/ksnip"
    bindsym $mod+comma move workspace to output left
    bindsym $mod+period move workspace to output right
    bindsym $mod+bracketright exec ${pkgs.pamixer}/bin/pamixer --increase 10
    bindsym $mod+bracketleft exec ${pkgs.pamixer}/bin/pamixer --decrease 10
    bindsym $mod+b exec --no-startup-id ${pkgs.xdotool}/bin/xdotool click 8
    bindsym $mod+shift+b exec --no-startup-id ${pkgs.xdotool}/bin/xdotool click 9
    ${lib.optionalString (i3Modifier != "Mod1") ''
      bindsym Mod1+b exec --no-startup-id ${pkgs.xdotool}/bin/xdotool click 8
      bindsym Mod1+shift+b exec --no-startup-id ${pkgs.xdotool}/bin/xdotool click 9
    ''}

    mode "resize" {
      bindsym j resize shrink width 10 px or 10 ppt
      bindsym k resize grow height 10 px or 10 ppt
      bindsym l resize shrink height 10 px or 10 ppt
      bindsym semicolon resize grow width 10 px or 10 ppt
      bindsym Shift+j resize shrink width 1 px or 1 ppt
      bindsym Shift+k resize grow height 1 px or 1 ppt
      bindsym Shift+l resize shrink height 1 px or 1 ppt
      bindsym Shift+semicolon resize grow width 1 px or 1 ppt
      bindsym Left resize shrink width 10 px or 10 ppt
      bindsym Down resize grow height 10 px or 10 ppt
      bindsym Up resize shrink height 10 px or 10 ppt
      bindsym Right resize grow width 10 px or 10 ppt
      bindsym Return mode "default"
      bindsym Escape mode "default"
      bindsym $mod+r mode "default"
    }

    mode "exit: [l]ogout, [r]eboot, [s]hutdown" {
      bindsym l exec ${pkgs.i3}/bin/i3-msg exit
      bindsym r exec systemctl reboot
      bindsym s exec systemctl shutdown
      bindsym Escape mode "default"
      bindsym Return mode "default"
    }
  '';

  local.tiling.generated.sway.keybindings = ''
    ${audioKeybindings "exec"}
    ${brightnessKeybindings "exec"}

    bindsym $mod+Return exec ${pkgs.alacritty}/bin/alacritty
    bindsym $mod+q kill
    bindsym $mod+d exec ${pkgs.rofi}/bin/rofi -modi drun\,run -show drun
    bindsym $mod+Shift+d exec ${pkgs.rofi}/bin/rofi -show window
    ${lib.optionalString hasTeams "bindsym $mod+F2 exec ${pkgs.teams-for-linux}/bin/teams-for-linux"}
    ${lib.optionalString swaySpotifyEnabled "bindsym $mod+F3 exec ${swaySpotifyCommand}"}

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
    bindsym Print exec ${editScreenshot}/bin/sway-edit-screenshot
    bindsym $mod+Shift+Print exec ${editScreenshot}/bin/sway-edit-screenshot
    bindsym $mod+comma move workspace to output left
    bindsym $mod+period move workspace to output right
    bindsym $mod+bracketright exec ${pkgs.pamixer}/bin/pamixer --increase 10
    bindsym $mod+bracketleft exec ${pkgs.pamixer}/bin/pamixer --decrease 10

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
  '';
}
