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
    # Management VLAN from CPM deployment hosts (URS: inventory → CPM → renderer)
    managementVlan =
      let
        hostDeploy = if cpmBuilt ? deploymentHosts then cpmBuilt.deploymentHosts.${hostName} or null else null;
      in
      if hostDeploy != null && hostDeploy ? uplinks then hostDeploy.uplinks.management or null else null;
    rendererInventoryJsonPath = builtins.toFile "renderer-inventory-${hostName}.json"
      (builtins.toJSON (import inventoryPath));
    # CPM_GAP: CPM does not yet emit bridgeControl for host-level bridges.
    bridgeControl = {
      dhcpServer = false;
      masquerade = "both";
    };
  };

  render-clab =
    inputs.network-renderer-containerlab-linux-backend.lib.renderer.canonical.hostModule
      rendererInput;

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
      render-clab
      render-nebula
      render-wireguard
      ;
    cpm = cpmBuilt;
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
