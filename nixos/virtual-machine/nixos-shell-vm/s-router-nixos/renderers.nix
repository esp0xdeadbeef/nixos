{ inputs
, lib
, relativeRepo
, labSource
, selectorFile
, system
, hostName ? "s-router-nixos"
,
}:

{ ... }:

let
  labPath = "${inputs.network-labs}/${labSource}";
  intentPath = "${labPath}/intent-${hostName}.nix";
  inventoryPath = "${labPath}/inventory-${hostName}.nix";
  sops = "${labPath}/sops-routing-${hostName}.nix";

  # FS-982: the host profile imports renderer output; bundle production lives
  # behind the producer boundary, not in the host profile.
  producer = import (relativeRepo.module "library/10-vms/nixos-shell-vm/renderer-pipeline-producer.nix") {
    inherit lib;
  };

  inventory = import inventoryPath;

  canonicalBundle = producer.realizeBundle {
    inherit
      system
      intentPath
      inventory
      hostName
      ;
    controlPlaneModelInput = inputs.network-control-plane-model;
    networkRealizationModelInput = inputs.network-realization-model;
    rootLockIdentity = builtins.hashString "sha256" (builtins.readFile ../../../../flake.lock);
  };

  rendererInput = {
    inherit hostName;
    bundle = canonicalBundle;
  };

  render-nixos =
    inputs.network-renderer-nixos.libBySystem.${system}.renderer.canonical.hostModule (
      rendererInput
      // {
        inherit lib selectorFile;
      }
    );

  render-nebula =
    inputs.network-renderer-nebula.libBySystem.${system}.renderer.canonical.hostModule
      rendererInput;

  render-wireguard =
    inputs.network-renderer-wireguard.libBySystem.${system}.renderer.canonical.hostModule
      rendererInput;

  # FS-982: the host profile does not expose CPM output, raw intent, or
  # inventory to downstream modules. Only the renderer output and the sops
  # routing module are exported.
  renderer-contract = {
    inherit
      canonicalBundle
      render-nebula
      render-nixos
      render-wireguard
      ;
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
}
