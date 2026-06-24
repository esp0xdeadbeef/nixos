{ pkgs, ... }:
{
  fonts.fontconfig.enable = true;

  home.packages = [
    pkgs.dejavu_fonts
    pkgs.font-awesome_6
    pkgs.noto-fonts-color-emoji
  ];
}
