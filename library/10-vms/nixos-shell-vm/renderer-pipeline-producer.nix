{ lib }:

# FS-982 renderer-output producer boundary.
#
# The host profile must not run the semantic pipeline or read raw intent / CPM
# output (FS-982; URS 104). Bundle production (intent + inventory through
# compiler -> NFM -> CPM -> realization-model, validated against the pinned
# schema) is owned HERE, behind one named boundary. The host profile calls
# `realizeBundle` and imports the returned renderer output; it never names
# compiler, NFM, CPM, intent, or inventory as behavior.
#
# The intent/inventory PATHS are inputs to this producer (source selection,
# allowed). Everything past selection is this producer's responsibility.
#
# This boundary covers the inputs every host profile needs:
# - intent + inventory (inventory may be a plain attrset or a { hostName }-arg
#   function, matching the existing host profiles),
# - an optional control-plane transform (default identity),
# - the renderer-input assembly and the optional VM NIC platform binding.

let
  attrsOrEmpty = a: if builtins.isAttrs a then a else { };

  # Resolve the inventory the way the host profiles do: a function expects
  # { hostName }, a plain attrset is used as-is.
  realizeInventory =
    { inventoryInput, hostName }:
    if builtins.isFunction inventoryInput then
      inventoryInput { inherit hostName; }
    else
      inventoryInput;

  # Build the canonical realization bundle from intent + inventory.
  realizeBundle =
    {
      controlPlaneModelInput,
      networkRealizationModelInput,
      system,
      intentPath,
      inventory,
      hostName,
      rootLockIdentity,
      controlPlaneTransform ? cpm: cpm,
    }:
    let
      resolvedInventory = realizeInventory { inventoryInput = inventory; inherit hostName; };
      cpmLib = controlPlaneModelInput.libBySystem.${system};
      inventoryExport = builtins.toFile "inventory.json" (builtins.toJSON resolvedInventory);
      cpmBuilt = cpmLib.compileAndBuildFromPaths {
        inputPath = intentPath;
        inventoryPath = inventoryExport;
      };
      cpmForRenderer = controlPlaneTransform cpmBuilt;
      artifactDigest = builtins.hashString "sha256" (builtins.toJSON cpmForRenderer);
      controlPlaneArtifact = {
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
    in
    networkRealizationModelInput.lib.realize {
      input = controlPlaneArtifact;
      requestScope = {
        kind = "complete-artifact";
        identity = hostName;
      };
      inherit rootLockIdentity;
      producerRevision =
        networkRealizationModelInput.rev
          or networkRealizationModelInput.dirtyRev
          or "uncommitted";
    };

  # VM NIC platform binding, built from the host profile's vmNics list. Kept
  # here (FS-982-SMS-130) so the host profile passes platform-binding material
  # to the producer instead of assembling it inline.
  vmNicsPlatformBinding =
    { hostName, vmNics, bundle }:
    if vmNics == [ ] then
      null
    else
      let
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
        nics = builtins.map vmNicForBinding vmNics;
        bindingBase = {
          kind = "network-platform-binding-bundle";
          schemaRevision = "network-platform-binding/v1";
          bundleIdentity = bundle.bundleIdentity;
          target = "nixos";
          requestScope = bundle.requestScope;
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
          schemaSetIdentity = bundle.validation.schemaSetIdentity;
        };
      };

in
{
  inherit
    realizeBundle
    realizeInventory
    vmNicsPlatformBinding
    ;
}
