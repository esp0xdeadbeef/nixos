{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  unstablePkgs = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in
{
  home.packages =
    let
      stable = with pkgs; [
        # koodo-reader # old version of electron
      ];
      unstable = with unstablePkgs; [
        koodo-reader # old version of electron
      ];
    in
    stable ++ unstable;
}
