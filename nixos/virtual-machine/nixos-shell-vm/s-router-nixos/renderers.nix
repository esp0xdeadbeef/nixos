{ inputs
, lib
, labSource
, selectorFile
, system
, hostName ? "s-router-nixos"
,
}:

{ ... }:

let
  labPath = "${inputs.network-labs}/${labSource}";
  intent = "${labPath}/intent.nix";
  inventory = "${labPath}/inventory-nixos.nix";
  sops = "${labPath}/sops-routing-${hostName}.nix";

  rendererInput = {
    inherit hostName intent inventory;
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
