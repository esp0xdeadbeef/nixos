{ outPath, ... }:
{
  imports = [
    "${outPath}/profiles/home-manager/desktop/window-manager.nix"
    "${outPath}/profiles/home-manager/desktop/pentest-windows.nix"
    "${outPath}/home-manager/01-general/darkmode/config.nix"
    "${outPath}/home-manager/01-general/editors/vscode.nix"
    "${outPath}/home-manager/01-general/pdf-reader/packages.nix"
    "${outPath}/home-manager/01-general/virt-manager-config/default.nix"
    "${outPath}/profiles/home-manager/nix/github-access-token.nix"
    "${outPath}/home-manager/02-window-manager-i3/i3/packages.nix"
    "${outPath}/home-manager/02-window-manager-i3/i3status-rust/packages.nix"
  ];
}
