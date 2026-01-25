{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./networking.nix
    #./podman-hello-world.nix
    ./debug-packages.nix
    #./podman-fix.nix
    ./containerlab.nix
  ];
  networking.useHostResolvConf = false;

  system.stateVersion = "25.11";
}
