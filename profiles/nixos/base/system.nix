{ outPath, ... }:
{
  nix.settings = {
    accept-flake-config = true;
  };

  imports = [
    "${outPath}/library/01-general/system/locale.nix"
    "${outPath}/library/01-general/terminals/tmux/settings.nix"
    "${outPath}/library/01-general/time/timezone.nix"
  ];
}
