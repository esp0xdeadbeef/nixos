{ relativeRepo, ... }:
{
  imports = [
    (relativeRepo.module "library/01-general/packages/default.nix")
    (relativeRepo.module "library/01-general/password-cracking/default.nix")
  ];
}
