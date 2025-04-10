{ config, pkgs, ... }:

{
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      font-awesome
      font-awesome_6
      powerline-fonts
      #nerdfonts
      terminus_font
      noto-fonts
      noto-fonts-emoji
      dejavu_fonts
      liberation_ttf
    ];

    fontconfig.defaultFonts = {
      monospace = [
        "DejaVu Sans Mono"
        "Terminus"
        "JetBrainsMono Nerd Font"
      ];
      sansSerif = [
        "Noto Sans"
        "DejaVu Sans"
        "Liberation Sans"
      ];
      serif = [
        "Noto Serif"
        "DejaVu Serif"
        "Liberation Serif"
      ];
      emoji = [ "Noto Color Emoji" ];
    };
  };
}
