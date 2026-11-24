# Keep Python bytecode out of the store and the repo tree.
#
# CPython writes `__pycache__` next to the sources by default, which in a Nix
# store path is impossible and in a checkout pollutes `git status` and makes
# builds non-reproducible. Pointing PYTHONPYCACHEPREFIX at /dev/shm keeps the
# bytecode in RAM, where it is worthless to persist anyway.
{
  environment.variables.PYTHONPYCACHEPREFIX = "/dev/shm";

  environment.shellInit = ''
    export PYTHONPYCACHEPREFIX="/dev/shm"
  '';
}
