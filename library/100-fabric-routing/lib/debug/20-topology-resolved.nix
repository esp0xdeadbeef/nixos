let
  pkgs = import <nixpkgs> {};
  lib  = pkgs.lib;
  cfg  = import ./00-inputs.nix;

  raw =
    import ./10-topology-raw.nix;
in
import ../topology-resolve.nix {
  inherit lib;
  inherit (cfg) ulaPrefix tenantV4Base;
} raw


