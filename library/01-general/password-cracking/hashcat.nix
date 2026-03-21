{ config, pkgs, ... }:

let
  pkgsCuda = import pkgs.path {
    system = pkgs.stdenv.hostPlatform.system;
    config = {
      allowUnfree = true;
      cudaSupport = true;
    };
  };
in
{
  environment.systemPackages = [
    pkgsCuda.hashcat
    pkgsCuda.cudaPackages.cudatoolkit
  ];
}
