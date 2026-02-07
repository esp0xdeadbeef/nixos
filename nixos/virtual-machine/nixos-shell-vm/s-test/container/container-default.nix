# ./container/default.nix
{
  lib,
  outPath,
  config,
  ...
}:
{
  imports = [
    "${outPath}/library/11-containers/nixos-container"
    ./containerlab.nix
    ./podman-hello-world.nix
    ./network.nix
  ];
}
