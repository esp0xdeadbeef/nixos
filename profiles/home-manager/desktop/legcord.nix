{ config, lib, pkgs, ... }:

let
  cfg = config.local.desktop.legcord;
in
{
  imports = [
    ./window-manager.nix
  ];

  options.local.desktop.legcord = {
    enable = lib.mkEnableOption "Legcord desktop integration";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.legcord
    ];

    local.i3.extraConfig = lib.mkAfter ''
      bindsym $mod+F4 exec ${pkgs.legcord}/bin/legcord
      for_window [class="legcord"] move to workspace 5
      exec --no-startup-id ${pkgs.legcord}/bin/legcord
    '';
  };
}
