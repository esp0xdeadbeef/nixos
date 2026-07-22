{ relativeRepo, ... }:
{
  imports = [
    (relativeRepo.module "library/03-window-manager-sway/default.nix")
  ];
}
