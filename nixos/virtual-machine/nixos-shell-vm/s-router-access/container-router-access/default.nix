{
  outPath,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./container-settings.nix
    ./options.nix
    ../debugging-packages.nix
  ];
}
