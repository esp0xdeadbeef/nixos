let
  pkgs = null;
  lib = import <nixpkgs/lib>;
  cfg = import ./inputs.nix;
in
import ../topology-gen.nix { inherit lib; } {
  inherit (cfg)
    tenantVlans
    policyAccessTransitBase
    corePolicyTransitVlan
    ;
}
