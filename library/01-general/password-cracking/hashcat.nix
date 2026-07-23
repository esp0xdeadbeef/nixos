{ config
, lib
, pkgs
, ...
}:

let
  cudaCapabilities = config.nixpkgs.config.cudaCapabilities or [ ];
  pkgsCuda = import pkgs.path {
    system = pkgs.stdenv.hostPlatform.system;
    config =
      {
        allowUnfree = true;
        cudaSupport = true;
      }
      // lib.optionalAttrs (cudaCapabilities != [ ]) {
        inherit cudaCapabilities;
        cudaForwardCompat = config.nixpkgs.config.cudaForwardCompat or false;
      };
  };
in
{
  environment.systemPackages = [
    pkgsCuda.hashcat
    pkgsCuda.cudaPackages.cudatoolkit
  ];
}
