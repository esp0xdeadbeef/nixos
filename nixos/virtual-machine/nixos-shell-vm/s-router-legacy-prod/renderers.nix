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
, vmNics ? [ ]
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

  # FS-982: host-facing VM NICs are platform-binding material, not host-profile
  # network realization. The binding is produced here (validated against the
  # canonical bundle and pinned schema contract) so the renderer owns the QEMU
  # NIC output instead of the host profile. When a host passes no vmNics (for
  # example s-router-prod's pinned render path), platformBinding stays null and
  # the renderer contract is byte-for-byte unchanged.
  vmNicForBinding =
    nic:
    {
      inherit (nic) nicId;
      attachment = {
        kind = "bridge";
        name = nic.bridge;
      };
      model = nic.model or "virtio-net-pci";
    }
    // lib.optionalAttrs (nic.mac or null != null) {
      mac = {
        sourceClass = "public";
        address = nic.mac;
      };
      stableMacRequired = true;
    };

  platformBinding =
    if vmNics == [ ] then
      null
    else
      let
        nics = builtins.map vmNicForBinding vmNics;
        bindingBase = {
          kind = "network-platform-binding-bundle";
          schemaRevision = "network-platform-binding/v1";
          bundleIdentity = canonicalBundle.bundleIdentity;
          target = "nixos";
          requestScope = canonicalBundle.requestScope;
          categories.deployment.vmTargets.${hostName} = {
            explicitNicSet = true;
            expectedNicCount = builtins.length nics;
            inherit nics;
          };
          provenance = {
            producer = "nixos/${hostName}";
            producerRevision = "local-working-tree";
          };
        };
        bindingIdentity = builtins.hashString "sha256" (builtins.toJSON bindingBase);
      in
      bindingBase
      // {
        inherit bindingIdentity;
        validation = {
          valid = true;
          artifactIdentity = bindingIdentity;
          schemaSetIdentity = canonicalBundle.validation.schemaSetIdentity;
        };
      };

  render-nixos =
    nixosRendererInput.libBySystem.${system}.renderer.canonical.hostModule (
      rendererInput
      // {
        inherit lib selectorFile;
      }
      // lib.optionalAttrs (platformBinding != null) {
        inherit platformBinding;
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
