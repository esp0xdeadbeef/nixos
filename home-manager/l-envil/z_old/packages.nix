{ config
, pkgs
, nixpkgs-unstable
, ...
}:

{
  home.username = "deadbeef";
  home.homeDirectory = "/home/deadbeef";

  # Packages related to Sway
  home.packages = with pkgs; [
    sway
    swaylock
    swayidle
    waybar
    rofi-wayland
    alacritty
    wofi
    mako # Notification daemon for Wayland
    brightnessctl
    pavucontrol
    grim
    slurp
    wl-clipboard
  ];

  # Sway Configuration
  home.file.".config/sway/config".text = ''
    set $mod Mod4
    exec waybar
    exec mako
    exec swayidle -w timeout 300 'swaylock -f' timeout 600 'systemctl suspend'

    # Basic keybindings
    bindsym $mod+Return exec alacritty
    bindsym $mod+d exec rofi -show drun
    bindsym $mod+Shift+q kill
    bindsym $mod+Shift+e exec "swaymsg exit"

    # Workspaces
    set $workspace1 "1: "
    set $workspace2 "2: "
    set $workspace3 "3: "
    bindsym $mod+1 workspace $workspace1
    bindsym $mod+2 workspace $workspace2
    bindsym $mod+3 workspace $workspace3

    # Floating mode
    bindsym $mod+Shift+space floating toggle
  '';

  # Waybar Configuration
  home.file.".config/waybar/config".text = ''
    {
      "layer": "top",
      "modules-left": ["sway/workspaces", "sway/mode"],
      "modules-center": ["clock"],
      "modules-right": ["battery", "network", "pulseaudio"]
    }
  '';

  # Enable Home Manager itself
  programs.home-manager.enable = true;
}
