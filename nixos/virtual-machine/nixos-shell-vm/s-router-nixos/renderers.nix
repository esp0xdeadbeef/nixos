{ inputs
, lib
, labSource
, selectorFile
, hostName ? "s-router-nixos"
,
}:

{ pkgs
, ...
}:

let
  system = pkgs.stdenv.hostPlatform.system or "x86_64-linux";
  labPath = "${inputs.network-labs}/${labSource}";
  intent = "${labPath}/intent.nix";
  inventory =
    if builtins.pathExists "${labPath}/inventory-nixos.nix" then
      "${labPath}/inventory-nixos.nix"
    else if builtins.pathExists "${labPath}/getResolvedInventory.nix" then
      builtins.toFile "s-router-nixos-inventory.nix" ''
        import ${labPath}/getResolvedInventory.nix { renderer = "nixos"; }
      ''
    else
      "${labPath}/inventory.nix";

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
    sops-for-renderers = ./sops.nix;
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
