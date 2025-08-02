{ config, pkgs, ... }:

{
  # Packages related to Sway
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
    rofi-wayland
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
