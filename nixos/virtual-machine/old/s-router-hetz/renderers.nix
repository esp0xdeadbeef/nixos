{ inputs
, lib
, labSource
, selectorFile
, system
, hostName ? "s-router-hetz"
,
}:

{ ... }:

let
  labPath = "${inputs.network-labs}/${labSource}";
  sops = "${labPath}/sops-routing-${hostName}.nix";

  cpmLib = inputs.network-control-plane-model.libBySystem.${system};

  cpmBuilt = cpmLib.compileAndBuildFromPaths {
    inputPath = "${labPath}/intent.nix";
    inventoryPath = "${labPath}/inventory-hetz.nix";
  };

  rendererInput = {
    inherit hostName;
    cpm = cpmBuilt;
    controlPlane = cpmBuilt;
  };

  render-nixos =
    inputs.network-renderer-nixos.libBySystem.${system}.renderer.hostModule (
      rendererInput
      // {
        inherit lib selectorFile;
      }
    );

  render-nebula =
    inputs.network-renderer-nebula.libBySystem.${system}.renderer.hostModule
      rendererInput;

  render-wireguard =
    inputs.network-renderer-wireguard.libBySystem.${system}.renderer.hostModule
      rendererInput;

  renderer-contract = {
    inherit render-nixos render-nebula render-wireguard;
    sops-for-renderers = sops;
  };
in
{
  imports = [
    render-nixos
    render-nebula
    render-wireguard
    renderer-contract.sops-for-renderers
  ];

  _module.args.sRouterNixosRenderers = renderer-contract;
}
