# lib/topology.nix
{ ulaPrefix ? "fd42:dead:beef", tenantV4Base ? "10.10" }:

let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;

  raw =
    import ./topology-gen.nix { inherit lib; } {
      tenantVlans = [ 10 20 30 40 50 60 70 80 ];
      policyAccessTransitBase = 100;
      corePolicyTransitVlan = 200;
    };

  resolved =
    import ./topology-resolve.nix {
      inherit lib ulaPrefix tenantV4Base;
    } raw;

  routed =
    import ./routing-gen.nix {
      inherit lib ulaPrefix tenantV4Base;
    } resolved;

in
routed


