{ outPath, ... }:
{
  imports = [
    "${outPath}/library/03-window-manager-sway/default.nix"
  ];
}
