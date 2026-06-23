{ lib, outPath, pkgs, ... }:
{
  imports = [
    "${outPath}/profiles/home-manager/desktop/window-manager.nix"
    "${outPath}/profiles/home-manager/desktop/pentest-windows.nix"
    "${outPath}/home-manager/01-general/darkmode/config.nix"
    "${outPath}/home-manager/01-general/editors/vscode.nix"
    "${outPath}/home-manager/01-general/pdf-reader/packages.nix"
    "${outPath}/home-manager/01-general/virt-manager-config/default.nix"
    "${outPath}/home-manager/03-window-manager-sway/wayland/sway/configs.nix"
    "${outPath}/home-manager/02-window-manager-i3/i3status-rust/packages.nix"
  ];

  home.packages = [
    pkgs.copyq
  ];

  local.sway.extraConfig = lib.mkAfter ''
    exec ${pkgs.copyq}/bin/copyq
    bindsym $mod+Shift+v exec ${pkgs.copyq}/bin/copyq show
  '';
}
