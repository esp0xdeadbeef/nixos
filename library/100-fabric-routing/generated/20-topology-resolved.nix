{ lib }:
let
  cfg = import ../inputs;
  raw = import ./10-topology-raw.nix { inherit lib; };
in
import ../lib/topology-resolve.nix {
  inherit lib;
  inherit (cfg) ulaPrefix tenantV4Base;
} raw
