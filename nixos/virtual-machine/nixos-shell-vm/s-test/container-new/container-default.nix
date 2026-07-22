# ./container/default.nix
{ lib
, relativeRepo
, config
, ...
}:
{
  imports = [
    (relativeRepo.module "library/11-containers/nixos-container")
    #./containerlab.nix
    #./podman-hello-world.nix
    ./network.nix
  ];
}
