# lib/debug/40-node.nix
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;
  cfg = import ./00-inputs.nix;

  node = "s-router-access-10";

  routed = import ./30-routing.nix;
in
import ./view-node.nix {
  inherit lib pkgs;
  inherit (cfg) ulaPrefix tenantV4Base;
} node routed
