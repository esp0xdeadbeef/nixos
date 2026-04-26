{
  config,
  lib,
  pkgs,
  sopsSecrets,
  ...
}:
let
  thunar = pkgs.thunar or pkgs.xfce.thunar;
in

{
  # sops = {
  #     secrets.burpLicenseCompanyname = { };
  #     secrets.remminaOfficeIP = { };
  #     secrets.remminaPentestIP = { };
  #     secrets.workRelatedXlsx = {};
  # };
  # use this in the config.nix if using swaylock:
  # security.pam.services.swaylock.enableGnomeKeyring = true;
  home.file."${config.home.homeDirectory}/.config/sway/config" = {
    text = ''
      # Default config for sway
      #
      # Copy this to ~/.config/sway/config and edit it to your liking.
      #
      # Read `man 5 sway` for a complete reference.

      ### Variables
      #
      # Logo key. Use Mod1 for Alt.
      set $mod Mod4
      # Home row direction keys, like vim
      set $left h
      set $down j
      set $up k
      set $right l
      # Your preferred terminal emulator
      set $term foot
      # Your preferred application launcher
      # set $menu wmenu-run
      set $menu "${pkgs.rofi}/bin/rofi -modi drun,run -show drun"

      ### Output configuration
      #
      # Default wallpaper (more resolutions are available in /run/current-system/sw/share/backgrounds/sway/)
      output * bg /run/current-system/sw/share/backgrounds/sway/Sway_Wallpaper_Blue_1920x1080.png fill
      #
      # Example configuration:
      #
      #   output HDMI-A-1 resolution 1920x1080 position 1920,0
      #
      # You can get the names of your outputs by running: swaymsg -t get_outputs

      ### Idle configuration
      #
      # Example configuration:
      #
      # exec swayidle -w \
      #          timeout 300 'swaylock -f -c 000000' \
      #          timeout 600 'swaymsg "output * power off"' resume 'swaymsg "output * power on"' \
      #          before-sleep 'swaylock -f -c 000000'
      #
      # This will lock your screen after 300 seconds of inactivity, then turn off
      # your displays after another 300 seconds, and turn your screens back on when
      # resumed. It will also lock your screen before your computer goes to sleep.

      ### Input configuration
      #
      # Example configuration:
      #
      #   input "2:14:SynPS/2_Synaptics_TouchPad" {
      #       dwt enabled
      #       tap enabled
      #       natural_scroll enabled
      #       middle_emulation enabled
      #   }
      #
      # You can get the names of your inputs by running: swaymsg -t get_inputs
      # Read `man 5 sway-input` for more information about this section.

      ### Key bindings
      #
      # Basics:
      #
      # Start a terminal
      bindsym $mod+Return exec $term

      # Kill focused window
      bindsym $mod+q kill

      # Start your launcher
      bindsym $mod+d exec $menu

      # Drag floating windows by holding down $mod and left mouse button.
      # Resize them with right mouse button + $mod.
      # Despite the name, also works for non-floating windows.
      # Change normal to inverse to use left mouse button for resizing and right
      # mouse button for dragging.
      floating_modifier $mod normal

      # Reload the configuration file
      bindsym $mod+Shift+r reload

      # Exit sway (logs you out of your Wayland session)
      bindsym $mod+Shift+e exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit sway? This will end your Wayland session.' -B 'Yes, exit sway' 'swaymsg exit'
      #
      # Moving around:
      #
      # Move your focus around
      bindsym $mod+$left focus left
      bindsym $mod+$down focus down
      bindsym $mod+$up focus up
      bindsym $mod+$right focus right
      # Or use $mod+[up|down|left|right]
      bindsym $mod+Left focus left
      bindsym $mod+Down focus down
      bindsym $mod+Up focus up
      bindsym $mod+Right focus right

      # Move the focused window with the same, but add Shift
      bindsym $mod+Shift+$left move left
      bindsym $mod+Shift+$down move down
      bindsym $mod+Shift+$up move up
      bindsym $mod+Shift+$right move right
      # Ditto, with arrow keys
      bindsym $mod+Shift+Left move left
      bindsym $mod+Shift+Down move down
      bindsym $mod+Shift+Up move up
      bindsym $mod+Shift+Right move right
      #
      # Workspaces:
      #
      # Switch to workspace
      bindsym $mod+1 workspace number 1
      bindsym $mod+2 workspace number 2
      bindsym $mod+3 workspace number 3
      bindsym $mod+4 workspace number 4
      bindsym $mod+5 workspace number 5
      bindsym $mod+6 workspace number 6
      bindsym $mod+7 workspace number 7
      bindsym $mod+8 workspace number 8
      bindsym $mod+9 workspace number 9
      bindsym $mod+0 workspace number 10
      # Move focused container to workspace
      bindsym $mod+Shift+1 move container to workspace number 1
      bindsym $mod+Shift+2 move container to workspace number 2
      bindsym $mod+Shift+3 move container to workspace number 3
      bindsym $mod+Shift+4 move container to workspace number 4
      bindsym $mod+Shift+5 move container to workspace number 5
      bindsym $mod+Shift+6 move container to workspace number 6
      bindsym $mod+Shift+7 move container to workspace number 7
      bindsym $mod+Shift+8 move container to workspace number 8
      bindsym $mod+Shift+9 move container to workspace number 9
      bindsym $mod+Shift+0 move container to workspace number 10
      # Note: workspaces can have any name you want, not just numbers.
      # We just use 1-10 as the default.
      #
      # Layout stuff:
      #
      # You can "split" the current object of your focus with
      # $mod+b or $mod+v, for horizontal and vertical splits
      # respectively.
      bindsym $mod+b splith
      bindsym $mod+v splitv

      # Switch the current container between different layout styles
      bindsym $mod+s layout stacking
      bindsym $mod+w layout tabbed
      bindsym $mod+e layout toggle split

      # Make the current focus fullscreen
      bindsym $mod+f fullscreen

      # Toggle the current focus between tiling and floating mode
      bindsym $mod+Shift+space floating toggle

      # Swap focus between the tiling area and the floating area
      bindsym $mod+space focus mode_toggle

      # Move focus to the parent container
      bindsym $mod+a focus parent
      #
      # Scratchpad:
      #
      # Sway has a "scratchpad", which is a bag of holding for windows.
      # You can send windows there and get them back later.

      # Move the currently focused window to the scratchpad
      bindsym $mod+Shift+minus move scratchpad

      # Show the next scratchpad window or hide the focused scratchpad window.
      # If there are multiple scratchpad windows, this command cycles through them.
      bindsym $mod+minus scratchpad show
      #
      # Resizing containers:
      #
      mode "resize" {
      # left will shrink the containers width
      # right will grow the containers width
      # up will shrink the containers height
      # down will grow the containers height
      bindsym $left resize shrink width 10px
      bindsym $down resize grow height 10px
      bindsym $up resize shrink height 10px
      bindsym $right resize grow width 10px

      # Ditto, with arrow keys
      bindsym Left resize shrink width 10px
      bindsym Down resize grow height 10px
      bindsym Up resize shrink height 10px
      bindsym Right resize grow width 10px

      # Return to default mode
      bindsym Return mode "default"
      bindsym Escape mode "default"
      }
      bindsym $mod+r mode "resize"
      #
      # Utilities:
      #
      # Special keys to adjust volume via PulseAudio
      bindsym --locked XF86AudioMute exec pactl set-sink-mute \@DEFAULT_SINK@ toggle
      bindsym --locked XF86AudioLowerVolume exec pactl set-sink-volume \@DEFAULT_SINK@ -5%
      bindsym --locked XF86AudioRaiseVolume exec pactl set-sink-volume \@DEFAULT_SINK@ +5%
      bindsym --locked XF86AudioMicMute exec pactl set-source-mute \@DEFAULT_SOURCE@ toggle
      # Special keys to adjust brightness via brightnessctl
      bindsym --locked XF86MonBrightnessDown exec brightnessctl set 5%-
      bindsym --locked XF86MonBrightnessUp exec brightnessctl set 5%+
      # Special key to take a screenshot with grim
      bindsym Print exec grim

      #
      # Status Bar:
      #
      # Read `man 5 sway-bar` for more information about this section.
      # bar {
      #     position top

      #     # When the status_command prints a new line to stdout, swaybar updates.
      #     # The default just shows the current date and time.
      #     # status_command while date +'%Y-%m-%d %X'; do sleep 1; done
      #     status_command waybar

      #     colors {
      #         statusline #ffffff
      #         background #323232
      #         inactive_workspace #32323200 #32323200 #5c5c5c
      #     }
      # }
      exec_always --no-startup-id ${pkgs.waybar}/bin/waybar

      include /etc/sway/config.d/*

      # gaps inner 15
      # gaps outer 10
      # smart_gaps on


      # deadbeefs config
      focus_follows_mouse no
      gaps inner 2
      gaps outer 2

      mode "exit:M [l]ogout, [r]eboot, [s]hutdown" {
        bindsym l exec ${pkgs.i3}/bin/i3-msg exit
        bindsym r exec systemctl reboot
        bindsym s exec systemctl shutdown
        bindsym Escape mode "default"
        bindsym Return mode "default"
      }
      bindsym $mod+m mode "exit: [l]ogout, [r]eboot, [s]hutdown"

      bindsym $mod+i exec ${thunar}/bin/thunar
      bindsym $mod+F4 exec ${pkgs.legcord}/bin/legcord

      bindsym $mod+Escape exec ${pkgs.i3lock}/bin/i3lock -n -i /home/deadbeef/Pictures/background/captureWebpageEachMonitorDifferentPage/img/combined_screenshot.png
      bindsym $mod+c exec google-chrome-stable
      bindsym $mod+F3 exec ${pkgs.spotify}/bin/spotify
      exec --no-startup-id ${pkgs.networkmanagerapplet}/bin/nm-applet

      # flameshot crashes
      # bindsym Print exec "${pkgs.flameshot}/bin/flameshot gui"
      # Replace Flameshot with Ksnip for Print key
      # bindsym Print exec "sway-screenshot -m region"
      # bindsym $mod+Print+Shift exec "sway-screenshot -m window -- mirage"

      # Add Alt + Print to open Ksnip
      bindsym $mod+Print exec "${pkgs.ksnip}/bin/ksnip"

      # move workspace to the left.
      bindsym $mod+comma move workspace to output left
      bindsym $mod+period move workspace to output right


      bindsym $mod+bracketright exec ${pkgs.pamixer}/bin/pamixer --increase 10
      bindsym $mod+bracketleft exec ${pkgs.pamixer}/bin/pamixer --decrease 10

      for_window [class="google-chrome" class="Google-chrome"] move window to workspace 2
      for_window [class="Chromium" title=".*"] move container to workspace 2
      for_window [class="Spotify"] move to workspace 4
      for_window [class="discord"] move to workspace 5
      for_window [class="legcord"] move to workspace 5
      for_window [class="Navigator" class="firefox"] move window to workspace 8
      for_window [class="Firefox"] move window to workspace 8
      for_window [class="firefox"] move window to workspace 8

      # bindsym $mod+b exec --no-startup-id ${pkgs.xdotool}/bin/xdotool click 8
      # bindsym $mod+shift+b exec --no-startup-id ${pkgs.xdotool}/bin/xdotool click 9
      # bindsym Mod1+b exec --no-startup-id ${pkgs.xdotool}/bin/xdotool click 8
      # bindsym Mod1+shift+b exec --no-startup-id ${pkgs.xdotool}/bin/xdotool click 9



      exec --no-startup-id export XDG_SESSION_TYPE=x11
      exec --no-startup-id xsetroot -solid "#333333" #gray
      exec --no-startup-id xsetroot -solid "#000000"
      exec --no-startup-id ${pkgs.picom}/bin/picom
      exec --no-startup-id ${pkgs.autorandr}/bin/autorandr
      exec --no-startup-id ${pkgs.dunst}/bin/dunst
      exec --no-startup-id ${pkgs.legcord}/bin/legcord

      # disable numlock
      exec --no-startup-id ${pkgs.numlockx}/bin/numlockx off
      exec_always --no-startup-id ${pkgs.autotiling}/bin/autotiling
      # exec_always --no-startup-id ${pkgs.dropbox}/bin/dropbox
      exec_always --no-startup-id ${pkgs.spotify}/bin/spotify
      # output DP-5 resolution 3840x2160 scale 1.25 position 0 0
      # output DP-6 resolution 3840x2160 scale 1.25 position 3072 0
      # output eDP-1 resolution 1920x1080 scale 1 position 6144 0

    '';
    # path = "${config.home.homeDirectory}/.config/i3/config";
  };
  home.packages = with pkgs; [
    # sway itself:
    sway
    # lock screen
    swaylock
    # ??
    swayidle
    # bar
    waybar

    # rofi but then wayland:

    wofi
    # Notification daemon for Wayland
    mako
    # simular to xclip
    wl-clipboard
    # brightness
    brightnessctl
    # audio
    pavucontrol
    # screenshot tooling:
    grim
    slurp
    # terminal (just to be sure)
    alacritty
  ];
}
