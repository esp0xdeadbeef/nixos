{ config, lib, pkgs, ... }:

let
  cfg = config.local.desktop.legcord;
  legcordPersistent = pkgs.writeShellScriptBin "legcord-persistent" ''
    exec ${pkgs.legcord}/bin/legcord \
      --password-store=basic \
      --user-data-dir="$HOME/.config/legcord" \
      "$@"
  '';
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
      legcordPersistent
    ];

    local.i3.extraConfig = lib.mkAfter ''
      bindsym $mod+F4 exec ${legcordPersistent}/bin/legcord-persistent
      for_window [class="legcord"] move to workspace 5
      exec_always --no-startup-id ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pgrep -u "$USER" -f "share/lib/[l]egcord/resources/app.asar" >/dev/null || exec ${legcordPersistent}/bin/legcord-persistent'
    '';
  };
}
