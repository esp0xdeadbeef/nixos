{ lib, outPath, ... }:
{
  imports = [
    ./base.nix
    "${outPath}/profiles/home-manager/desktop/pentest-windows.nix"
    "${outPath}/home-manager/01-general/darkmode/config.nix"
    "${outPath}/home-manager/01-general/editors/vscode.nix"
    "${outPath}/home-manager/01-general/pdf-reader/packages.nix"
    "${outPath}/home-manager/01-general/virt-manager-config/default.nix"
    "${outPath}/profiles/home-manager/nix/github-access-token.nix"
  ];

  local.i3.spotify.enable = lib.mkDefault true;
}
