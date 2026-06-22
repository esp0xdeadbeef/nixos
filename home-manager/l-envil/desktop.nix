{ config, lib, pkgs, ... }:
let
  unstablePkgs = pkgs.unstable;
in
{
  local.sway.statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config.toml";
  local.desktop.legcord.enable = true;

  local.tilingManagerSettings.extraConfig = lib.mkAfter ''
    # l-envil additions
    bindsym $mod+o exec ${pkgs.remmina}/bin/remmina -c "/home/deadbeef/.local/share/remmina/group_rdp_1-win11-office-libvirt.remmina"
    bindsym $mod+p exec ${pkgs.remmina}/bin/remmina -c "/home/deadbeef/.local/share/remmina/group_rdp_1-win11-pentest-libvirt.remmina"

    ${lib.optionalString config.local.work.microsoft.enable ''
      bindsym $mod+F2 exec ${pkgs.teams-for-linux}/bin/teams-for-linux
      for_window [class="teams-for-linux"] move window to workspace 5
    ''}
    ${lib.optionalString config.local.work.microsoft.enable ''
      exec ${pkgs.teams-for-linux}/bin/teams-for-linux
    ''}
  '';

  local.sway.extraConfig = lib.mkAfter ''
    ${lib.optionalString config.local.work.microsoft.enable ''
      for_window [app_id="teams-for-linux"] move window to workspace 5
    ''}
  '';

  home.packages =
    let
      stable = with pkgs; [
        black
        google-chrome
        htop
        obsidian
        tmuxp
      ];
      unstable = with unstablePkgs; [
        gh
      ];
    in
    stable ++ unstable;
}
