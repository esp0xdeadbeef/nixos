{ relativeRepo, ... }:
{
  imports = [
    (relativeRepo.module "library/01-general/desktop/default.nix")
  ];
}
