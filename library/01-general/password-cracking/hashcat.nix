{ config, pkgs, ... }:

let
  pkgsCuda = import pkgs.path {
    system = pkgs.system;
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
