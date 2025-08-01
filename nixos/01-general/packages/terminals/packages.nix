{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    alacritty
    xterm
    kitty
  ];
}
