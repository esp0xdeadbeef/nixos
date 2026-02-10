let
  pkgs = null;
  lib = import <nixpkgs/lib>;

  all = import ./90-all.nix;
  topoRaw = import ./10-topology-raw.nix;

  # Import the modular renderer (directory, not file)
  renderer = import ../render-networkd { inherit lib; };

in
renderer.render {
  inherit all;
  topologyRaw = topoRaw;
  nodeName = "s-router-access-10";
}

