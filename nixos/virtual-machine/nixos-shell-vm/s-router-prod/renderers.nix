{ inputs
, lib
, modelSource
, selectorFile
, system
, controlPlaneModelInput ? inputs.network-control-plane-model
, networkRealizationModelInput ? inputs.network-realization-model
, controlPlaneTransform ? cpm: cpm
, nixosRendererInput ? inputs.network-renderer-nixos
, wireguardRendererInput ? inputs.network-renderer-wireguard
, hostName ? "s-router-prod"
, inventoryFileName ? "inventory.nix"
, intentFileName ? "intent.nix"
,
}:

{ ... }:

let
  intentPath = "${modelSource}/${intentFileName}";
  inventoryPath = "${modelSource}/${inventoryFileName}";

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
        producer = "nixos/${hostName}";
        source = "network-control-plane-model";
      };
    };

  canonicalBundle = networkRealizationModelInput.lib.realize {
    input = controlPlaneArtifact;
    requestScope = {
      kind = "complete-artifact";
      identity = hostName;
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

  render-wireguard =
    wireguardRendererInput.libBySystem.${system}.renderer.canonical.hostModule (
      rendererInput
      // {
        inherit lib;
        inherit
          providerContracts
          wgInventory
          ;
      }
    );

  providerContracts =
    let
      inventory = import inventoryPath;
      entries = lib.concatMap
        (enterpriseName:
          let sites = inventory.controlPlane.sites.${enterpriseName} or { };
          in
          lib.concatMap
            (siteName:
              let overlays = sites.${siteName}.overlays or { };
              in
              lib.concatMap
                (overlayName:
                  let pc = overlays.${overlayName}.providerContract or null;
                  in
                  if pc == null then [ ] else [{ name = overlayName; value = pc; }])
                (builtins.attrNames overlays))
            (builtins.attrNames sites))
        (builtins.attrNames (inventory.controlPlane.sites or { }));
    in
    { wireguard = builtins.listToAttrs entries; };

  wgInventory =
    let
      inventory = import inventoryPath;
      entries = lib.concatMap
        (enterpriseName:
          let sites = inventory.controlPlane.sites.${enterpriseName} or { };
          in
          lib.concatMap
            (siteName:
              let overlays = sites.${siteName}.overlays or { };
              in
              lib.concatMap
                (overlayName:
                  let
                    pc = overlays.${overlayName}.providerContract or null;
                    vpn = if builtins.isAttrs pc && builtins.isAttrs (pc.interfaces or null) then pc.interfaces.vpn or null else null;
                  in
                  if vpn == null then [ ] else [{ name = overlayName; value = { interface = vpn; }; }])
                (builtins.attrNames overlays))
            (builtins.attrNames sites))
        (builtins.attrNames (inventory.controlPlane.sites or { }));
    in
    builtins.listToAttrs entries;

  renderer-contract = {
    inherit canonicalBundle controlPlaneArtifact render-nixos;
    cpm = cpmForRenderer;
    inventory = import inventoryPath;
    inherit intentPath inventoryPath;
  };
in
{
  imports = [
    render-nixos
    render-wireguard
  ];

  _module.args.sRouterProdRenderers = renderer-contract;
  _module.args.sRouterProdModelSource = {
    inherit intentPath inventoryPath;
  };
}
