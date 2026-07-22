{ relativeRepo
, lib
, config
, ...
}:
{
  imports = [
    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config-router")
    ./mount-utils.nix
    ./container-settings.nix
  ];
}
