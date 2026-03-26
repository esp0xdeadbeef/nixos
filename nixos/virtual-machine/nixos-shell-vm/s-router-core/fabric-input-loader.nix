{ pkgs, inputs, fabricInputs, lib, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;

  inventoryImported = import ./inventory.nix;
  inventoryRaw =
    if builtins.isFunction inventoryImported then
      inventoryImported { inherit lib; }
    else
      inventoryImported;

  compilerOut =
    (inputs.nixos-network-compiler.lib.compile system) fabricInputs;

  forwardingOut =
    inputs.network-forwarding-model.lib.${system} {
      input = compilerOut;
    };

  controlPlaneLib = inputs.network-control-plane-model.lib;

  controlPlaneOut =
    if controlPlaneLib ? ${system} then
      let
        systemLib = builtins.getAttr system controlPlaneLib;
      in
      if systemLib ? build then
        systemLib.build {
          input = forwardingOut;
          inventory = inventoryRaw;
        }
      else
        throw ''
          fabric-input-loader:

          network-control-plane-model.lib.${system} exists but has no `build`.

          Available keys:
          ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames systemLib)}
        ''
    else if controlPlaneLib ? controlPlaneModel then
      controlPlaneLib.controlPlaneModel {
        input = forwardingOut;
        inventory = inventoryRaw;
      }
    else
      throw ''
        fabric-input-loader:

        Unsupported network-control-plane-model API.

        Available keys:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames controlPlaneLib)}
      '';
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
