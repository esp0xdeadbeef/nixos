{ relativeRepo, ... }:
{
  imports = [
    (relativeRepo.module "library/01-general/virtualization-as-host/lxc.nix")
  ];
}
