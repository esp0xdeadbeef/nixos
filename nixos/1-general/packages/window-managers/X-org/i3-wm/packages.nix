{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    playerctl
    i3status-rust
    light
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
