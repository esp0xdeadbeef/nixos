{ relativeRepo, ... }:
{
  imports = [
    (relativeRepo.module "library/01-general/system/autoupdate.nix")
    (relativeRepo.module "library/01-general/system/garbage-collection.nix")
  ];
}
