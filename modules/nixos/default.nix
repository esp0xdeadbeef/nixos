# Add your reusable NixOS modules to this directory, on their own file (https://nixos.wiki/wiki/Module).
# These should be stuff you would like to share with others, not your personal configurations.
{
  cudaCache = import ./cuda-cache.nix;
  containerNetworkDefaults = import ./container-network-defaults.nix;
  localUsers = import ./local-users.nix;
  pythonPycachePrefix = {
    environment.variables.PYTHONPYCACHEPREFIX = "/dev/shm";
    environment.shellInit = ''
      export PYTHONPYCACHEPREFIX="/dev/shm"
    '';
  };
}
