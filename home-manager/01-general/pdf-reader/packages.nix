{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  unstablePkgs = import inputs.nixpkgs-unstable {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{
  home.packages =
  let
    stable = with pkgs; [
      koodo-reader
    ];
    unstable = with unstablePkgs; [
    ];
  in
    stable ++ unstable;
}