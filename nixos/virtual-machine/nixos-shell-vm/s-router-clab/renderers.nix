{ inputs
, lib
, labSource
, selectorFile
, system
, hostName ? "s-router-clab"
,
}:

{ ... }:

let
  labPath = "${inputs.network-labs}/${labSource}";
  intent = "${labPath}/intent.nix";
  inventory = "${labPath}/inventory-clab.nix";
  sops = "${labPath}/sops-routing-${hostName}.nix";

  rendererInput = {
    inherit hostName intent inventory;
  };

  render-clab =
    inputs.network-renderer-containerlab-linux-backend.libBySystem.${system}.renderer.hostModule (
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
    inherit render-clab render-nebula render-wireguard;
    sops-for-renderers = sops;
  };
in
{
  imports = [
    render-clab
    render-nebula
    render-wireguard
    renderer-contract.sops-for-renderers
  ];

  _module.args.sRouterClabLabRenderers = renderer-contract;
}
