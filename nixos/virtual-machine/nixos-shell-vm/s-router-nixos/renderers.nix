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
  intentPath = "${labPath}/intent-${hostName}.nix";
  inventoryPath = "${labPath}/inventory-${hostName}.nix";
  sops = "${labPath}/sops-routing-${hostName}.nix";

  cpmLib = inputs.network-control-plane-model.libBySystem.${system};

  cpmBuilt = cpmLib.compileAndBuildFromPaths {
    inputPath = intentPath;
    inherit inventoryPath;
  };

  controlPlaneArtifact =
    let
      artifactDigest = builtins.hashString "sha256" (builtins.toJSON cpmBuilt);
    in
    {
      kind = "network-control-plane-artifact";
      artifactIdentity = artifactDigest;
      inherit artifactDigest;
      control_plane_model = cpmBuilt;
      authorityConflicts = [ ];
      provenance = {
        producer = "nixos/${hostName}";
        source = "network-control-plane-model";
      };
    };

  canonicalBundle = inputs.network-realization-model.lib.realize {
    input = controlPlaneArtifact;
    requestScope = {
      kind = "complete-artifact";
      identity = hostName;
    };
    rootLockIdentity = builtins.hashString "sha256" (builtins.readFile ../../../../flake.lock);
    producerRevision =
      inputs.network-realization-model.rev
        or inputs.network-realization-model.dirtyRev
        or "uncommitted";
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

  renderer-contract = {
    inherit
      canonicalBundle
      controlPlaneArtifact
      render-nebula
      render-nixos
      render-wireguard
      ;
    cpm = cpmBuilt;
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
