{ config, pkgs, ... }:
let
  azurehound = import ./build_package.nix {
    inherit (pkgs)
      stdenv
      lib
      fetchzip
      autoPatchelfHook
      glibc
      ;
  };
in
{
  environment.systemPackages = with pkgs; [
    azurehound
  ];
}
