{ relativeRepo, ... }:
{
  nix.settings = {
    accept-flake-config = true;
  };

  imports = [
    (relativeRepo.module "library/01-general/system/locale.nix")
    (relativeRepo.module "library/01-general/terminals/tmux/settings.nix")
    (relativeRepo.module "library/01-general/time/timezone.nix")
  ];
}
