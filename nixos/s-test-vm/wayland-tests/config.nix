{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    wl-clipboard
    wtype
    ydotool
    vscodium
  ];
}