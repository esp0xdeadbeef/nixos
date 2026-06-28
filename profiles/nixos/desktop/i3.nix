{ outPath, ... }:
{
  imports = [
    "${outPath}/library/01-general/packages/window-managers/X-org/packages.nix"
    "${outPath}/library/01-general/packages/window-managers/X-org/i3-wm/packages.nix"
    "${outPath}/library/02-window-manager-i3/default.nix"
  ];
}
