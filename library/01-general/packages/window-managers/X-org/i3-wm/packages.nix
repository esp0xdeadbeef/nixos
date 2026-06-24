{ config, lib, pkgs, ... }:
{
  config = lib.mkIf config.services.xserver.windowManager.i3.enable {
    environment.systemPackages = with pkgs; [
      alacritty
      autotiling
      autorandr
      betterlockscreen
      brightnessctl
      dunst
      flameshot
      i3status-rust
      ksnip
      playerctl
    ];
  };
}
