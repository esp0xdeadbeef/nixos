{ config
, outPath
, pkgs
, ...
}:

let
  modifier = config.local.i3.modifier;
  generated = config.local.tiling.generated.i3;
  extraConfig = ''
    ${config.local.i3.extraConfig}
    ${config.local.tilingManagerSettings.extraConfig}
  '';
in
{
  imports = [
    "${outPath}/profiles/home-manager/desktop/window-manager.nix"
  ];

  config = {
    home.packages = [
      pkgs.arandr
      pkgs.rofi
      pkgs.xdotool
    ];

    home.file."/.xprofile" = {
      text = ''
        export $(gnome-keyring-daemon --start --components=secrets,pkcs11,ssh,gpg)
      '';
      executable = true;
    };

    home.file."${config.home.homeDirectory}/.config/i3/config" = {
      force = true;
      text = ''
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
    };
  };
}
