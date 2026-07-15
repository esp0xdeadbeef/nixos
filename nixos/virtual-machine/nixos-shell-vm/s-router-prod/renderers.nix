{ inputs
, lib
, outPath
, modelSource
, selectorFile
, system
, controlPlaneModelInput ? inputs.network-control-plane-model
, controlPlaneTransform ? cpm: cpm
, nixosRendererInput ? inputs.network-renderer-nixos
, hostName ? "s-router-prod"
,
}:

{ ... }:

let
  intentPath = "${modelSource}/intent.nix";
  inventoryPath = "${modelSource}/inventory.nix";

  cpmLib = controlPlaneModelInput.libBySystem.${system};

  cpmBuilt = cpmLib.compileAndBuildFromPaths {
    inputPath = intentPath;
    inherit inventoryPath;
  };
  cpmForRenderer = controlPlaneTransform cpmBuilt;

  rendererInput = {
    inherit hostName;
    cpm = cpmForRenderer;
    controlPlane = cpmForRenderer;
  };

  render-nixos =
    nixosRendererInput.libBySystem.${system}.renderer.hostModule (
      rendererInput
      // {
        inherit lib selectorFile;
      }
    );

  renderer-contract = {
    inherit render-nixos;
    cpm = cpmForRenderer;
    inventory = import inventoryPath { };
    inherit intentPath inventoryPath;
  };
in
{
  imports = [
    render-nixos
  ];

  _module.args.sRouterProdRenderers = renderer-contract;
  _module.args.sRouterProdModelSource = {
    inherit intentPath inventoryPath;
  };
}
