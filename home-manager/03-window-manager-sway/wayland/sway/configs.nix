{ config
, pkgs
, ...
}:

let
  modifier = config.local.sway.modifier;
  generated = config.local.tiling.generated.sway;
  extraConfig = ''
    ${config.local.sway.extraConfig}
    ${config.local.tilingManagerSettings.extraConfig}
  '';
in
{
  home.packages = with pkgs; [
    alacritty
    autotiling
    brightnessctl
    grim
    mako
    networkmanagerapplet
    pamixer
    pavucontrol
    polkit_gnome
    rofi
    slurp
    sway
    sway-contrib.grimshot
    swayidle
    swaylock
    swappy
    wl-clipboard
    wofi
  ];

  home.file.".config/sway/config".text = ''
    set $mod ${modifier}

    font pango:monospace 10
    floating_modifier $mod
    focus_follows_mouse no
    gaps inner 2
    gaps outer 2
    smart_gaps on

    set $ws1 "1"
    set $ws2 "2"
    set $ws3 "3"
    set $ws4 "4"
    set $ws5 "5"
    set $ws6 "6"
    set $ws7 "7"
    set $ws8 "8"
    set $ws9 "9"
    set $ws10 "10"

    ${generated.autostart}
    ${generated.keybindings}
    ${generated.windowRules}
    ${generated.bar}
    ${extraConfig}
  '';
}
