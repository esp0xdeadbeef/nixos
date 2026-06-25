{ outPath, ... }:
{
  imports = [
    "${outPath}/home-manager/02-window-manager-i3/i3/packages.nix"
    "${outPath}/home-manager/02-window-manager-i3/i3status-rust/packages.nix"
  ];
}
