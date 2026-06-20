{ outPath, ... }:
{
  imports = [
    "${outPath}/library/01-general/system/autoupdate.nix"
    "${outPath}/library/01-general/system/garbage-collection.nix"
  ];
}
