{
  config,
  lib,
  pkgs,
  sopsSecrets,
  ...
}:

{
  home.file."/.config/nixpkgs/config.nix" = {
    text = ''
      { allowUnfree = true; }
    '';
  };
}
