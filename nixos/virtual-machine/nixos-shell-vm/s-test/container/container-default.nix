# ./container/default.nix
{ lib
, relativeRepo
, config
, ...
}:
{
  imports = [
    (relativeRepo.module "profiles/nixos/containers/nixos-container")
    ./containerlab.nix
    ./podman-hello-world.nix
    ./network.nix
  ];
}
