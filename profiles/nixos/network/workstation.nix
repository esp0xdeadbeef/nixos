{ outPath, ... }:
{
  imports = [
    "${outPath}/library/01-general/network/default.nix"
  ];
}
