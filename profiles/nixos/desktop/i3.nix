{ outPath, ... }:
{
  imports = [
    "${outPath}/library/02-window-manager-i3/default.nix"
  ];
}
