{ relativeRepo, ... }:
{
  imports = [
    (relativeRepo.module "library/01-general/packages/window-managers/X-org/packages.nix")
    (relativeRepo.module "library/01-general/packages/window-managers/X-org/i3-wm/packages.nix")
    (relativeRepo.module "library/02-window-manager-i3/default.nix")
  ];
}
