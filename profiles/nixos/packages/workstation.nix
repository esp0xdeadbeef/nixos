{ outPath, ... }:
{
  imports = [
    "${outPath}/library/01-general/packages/default.nix"
    "${outPath}/library/01-general/password-cracking/default.nix"
  ];
}
