{ inputs
, lib
, pkgs
, ...
}:

let
  modelHost = import ../../../s-router-model-host.nix {
    inherit inputs lib pkgs;
    selector = "s-router-test";
    file = "nixos/virtual-machine/nixos-shell-vm/s-router-test/default.nix";
    enableNebulaRenderer = false;
  };
in
import ./host-output.nix { inherit inputs lib pkgs modelHost; }
