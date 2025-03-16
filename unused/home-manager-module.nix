{ config, pkgs, nixpkgs-unstable, ... }:

{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.deadbeef = import ./home-manager/home.nix;
}

