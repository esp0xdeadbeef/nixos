{ inputs
, lib
, labSource
, selectorFile
, hostName ? "s-router-nixos"
,
}:

{ ... }:

let
  labPath = "${inputs.network-labs}/${labSource}";
  intent = "${labPath}/intent.nix";
  inventory = "${labPath}/inventory.nix";

  rendererInput = {
    inherit
      hostName
      intent
      inventory
      system
      ;
  };

  render-nixos = inputs.network-renderer-nixos.lib.renderer.hostModule (
    rendererInput
    // {
      inherit lib;
      selectorFile = selectorFile;
    }
  );

  render-nebula = inputs.network-renderer-nebula.libBySystem.${system}.renderer.hostModule rendererInput;

  render-wireguard = inputs.network-renderer-wireguard.libBySystem.${system}.renderer.hostModule rendererInput;

  renderer-contract = {
    inherit
      render-nixos
      render-nebula
      render-wireguard
      ;
    sops-for-renderers = "${labPath}/sops.nix";
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
