{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    playerctl
    i3status-rust
    brightnessctl
    alacritty
    betterlockscreen
    ksnip
    flameshot
    autorandr
    rofi
    # inotify service (otherwise flameshot crashes)
    dunst
    autotiling
  ];
}
