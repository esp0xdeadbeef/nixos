{ outPath, ... }:
{
  imports = [
    "${outPath}/modules/nixos/cuda-cache.nix"
    "${outPath}/modules/nixos/local-users.nix"

    "${outPath}/library/01-general/network/default.nix"
    "${outPath}/library/01-general/secrets/import-secrets.nix"
    "${outPath}/library/01-general/system/autoupdate.nix"
    "${outPath}/library/01-general/system/locale.nix"
    "${outPath}/library/01-general/system/garbage-collection.nix"
    "${outPath}/library/01-general/terminals/tmux/settings.nix"
    "${outPath}/library/01-general/time/timezone.nix"
  ];
}
