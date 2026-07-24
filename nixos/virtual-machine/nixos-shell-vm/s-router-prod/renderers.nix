{ inputs
, lib
, modelSource
, selectorFile
, system
, controlPlaneModelInput ? inputs.network-control-plane-model
, networkRealizationModelInput ? inputs.network-realization-model
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

  controlPlaneArtifact =
    let
      artifactDigest = builtins.hashString "sha256" (builtins.toJSON cpmForRenderer);
    in
    {
      kind = "network-control-plane-artifact";
      artifactIdentity = artifactDigest;
      inherit artifactDigest;
      control_plane_model = cpmForRenderer;
      authorityConflicts = [ ];
      provenance = {
        producer = "nixos/s-router-prod";
        source = "network-control-plane-model";
      };
    };

  canonicalBundle = networkRealizationModelInput.lib.realize {
    input = controlPlaneArtifact;
    requestScope = {
      kind = "complete-artifact";
      identity = "s-router-prod";
    };
    rootLockIdentity = builtins.hashString "sha256" (builtins.readFile ../../../../flake.lock);
    producerRevision =
      networkRealizationModelInput.rev
        or networkRealizationModelInput.dirtyRev
        or "uncommitted";
  };

  rendererInput = {
    inherit hostName;
    bundle = canonicalBundle;
  };

  render-nixos =
    nixosRendererInput.libBySystem.${system}.renderer.canonical.hostModule (
      rendererInput
      // {
        inherit lib selectorFile;
      }
    );

  renderer-contract = {
    inherit canonicalBundle controlPlaneArtifact render-nixos;
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
