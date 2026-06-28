{ config, lib, pkgs, ... }:
let
  unstablePkgs = pkgs.unstable;
in
{
  local.i3.statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config.toml";
  local.desktop.legcord.enable = true;

  local.tilingManagerSettings.extraConfig = lib.mkAfter ''
    # l-envil additions
    bindsym $mod+o exec ${pkgs.remmina}/bin/remmina -c "/home/deadbeef/.local/share/remmina/group_rdp_1-win11-office-libvirt.remmina"
    bindsym $mod+p exec ${pkgs.remmina}/bin/remmina -c "/home/deadbeef/.local/share/remmina/group_rdp_1-win11-pentest-libvirt.remmina"
  '';

  home.packages =
    let
      stable = with pkgs; [
        black
        brave
        chromium
        discord
        google-chrome
        htop
        lmstudio
        obsidian
        spotify
        tmuxp
      ];
      unstable = with unstablePkgs; [
        gh
      ];
    in
    stable ++ unstable;
}
