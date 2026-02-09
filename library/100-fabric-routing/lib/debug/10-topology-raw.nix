let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;
  cfg = import ./00-inputs.nix;
in
import ../topology-gen.nix { inherit lib; } {
  inherit (cfg)
    tenantVlans
    policyAccessTransitBase
    corePolicyTransitVlan
    ;
}
