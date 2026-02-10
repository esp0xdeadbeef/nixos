{ lib }:
let
  cfg = import ../inputs;
in
import ../lib/topology-gen.nix { inherit lib; } {
  inherit (cfg)
    tenantVlans
    policyAccessTransitBase
    corePolicyTransitVlan
    ;
}
