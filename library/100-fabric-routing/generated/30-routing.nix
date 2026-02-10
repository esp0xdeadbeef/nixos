{ lib }:
let
  cfg = import ../inputs;
  resolved = import ./20-topology-resolved.nix { inherit lib; };
in
import ../lib/routing-gen.nix {
  inherit lib;
  inherit (cfg) ulaPrefix tenantV4Base;
} resolved
