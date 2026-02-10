let
  pkgs = null;
  lib = import <nixpkgs/lib>;
  cfg = import ./inputs.nix;

  raw = import ./10-topology-raw.nix;
in
import ../topology-resolve.nix {
  inherit lib;
  inherit (cfg) ulaPrefix tenantV4Base;
} raw
