{ relativeRepo, ... }:
{
  imports = [
    (relativeRepo.module "library/01-general/network/default.nix")
  ];
}
