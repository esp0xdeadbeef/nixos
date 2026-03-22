{ pkgs, inputs, fabricInputs, lib, outPath, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  fabricInventory = import ./inventory.nix;

  compilerOut =
    (inputs.nixos-network-compiler.lib.compile system) fabricInputs;

  forwardingOut =
    inputs.network-forwarding-model.lib.${system} {
      input = compilerOut;
    };

  controlPlaneOut =
    inputs.network-control-plane-model.lib.controlPlaneModel {
      input = forwardingOut;
      inventory = fabricInventory;
    };
in
{
  _module.args = {
    inherit compilerOut forwardingOut controlPlaneOut;
    fabricCompiled = controlPlaneOut;
  };

  environment.etc."network-artifacts/compiler.json".text =
    builtins.toJSON compilerOut;

  environment.etc."network-artifacts/forwarding.json".text =
    builtins.toJSON forwardingOut;

  environment.etc."network-artifacts/control-plane.json".text =
    builtins.toJSON controlPlaneOut;
}
