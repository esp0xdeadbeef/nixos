{ pkgs, ... }:
{
  fonts.fontconfig.enable = true;

  home.packages = [
    pkgs.dejavu_fonts
    pkgs.font-awesome_6
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.noto-fonts-color-emoji
    pkgs.rofi
  ];
}
