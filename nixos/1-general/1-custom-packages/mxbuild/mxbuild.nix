{ config, pkgs, ... }:
let
  mxbuild = import ./build_mxbuild.nix {
    inherit (pkgs)
      stdenv
      lib
      fetchurl
      patchelf
      makeWrapper
      icu
      openssl
      ;
  };
in
{
  environment.systemPackages = with pkgs; [
    mxbuild
  ];
}
