# lib/topology.nix
{ }:

let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;

  raw =
    import ./topology-gen.nix { inherit lib; } {
      tenantVlans = [ 10 20 30 40 50 60 70 80 ];
      policyAccessTransitBase = 100;
      corePolicyTransitVlan = 200;
    };

in
import ./topology-resolve.nix { inherit lib; } raw

