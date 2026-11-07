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
    { controlPlaneModelInput
    , networkRealizationModelInput
    , system
    , intentPath
    , inventory
    , hostName
    , rootLockIdentity
    , controlPlaneTransform ? cpm: cpm
    ,
    }:
    (realizeAll {
      inherit
        controlPlaneModelInput
        networkRealizationModelInput
        system
        intentPath
        inventory
        hostName
        rootLockIdentity
        controlPlaneTransform
        ;
    }).bundle;

  # As realizeBundle, but also returns the CPM output so a host profile can read
  # platform-neutral deployment facts (for example deploymentHosts) without
  # calling the CPM itself.
  realizeAll =
    { controlPlaneModelInput
    , networkRealizationModelInput
    , system
    , intentPath
    , inventory
    , hostName
    , rootLockIdentity
    , controlPlaneTransform ? cpm: cpm
    ,
    }:
    let
      resolvedInventory = realizeInventory { inventoryInput = inventory; inherit hostName; };
      cpmLib = controlPlaneModelInput.libBySystem.${system};
      # Pass the resolved inventory attrset straight to the CPM.  It used to be
      # serialised with `builtins.toFile` and passed as a store-path STRING; in
      # pure evaluation (nix flake check) that string crosses the flake boundary
      # into the CPM's `libBySystem` with its store context stripped, so
      # `readFile` resolved the bare `<hash>-inventory.json` relative to CWD and
      # failed with "path ... is not valid".  The CPM's `readValue` accepts a
      # plain attrset and returns it unchanged, so no serialisation is needed.
      # (`compileAndBuildFromPaths` still takes the *intent* by path, which is a
      # real Nix path and keeps its context.)
      cpmBuilt = cpmLib.compileAndBuildFromPaths {
        inputPath = intentPath;
        inventoryPath = resolvedInventory;
      };
      cpmForRenderer = controlPlaneTransform cpmBuilt;
      # FS-310-SMS-100 / network-realization-schema: the artifact's
      # `control_plane_model` is the control-plane envelope
      # (`{ data = <enterprise -> site map>; version; ... }`). `compileAndBuild`
      # returns a build result that also carries `endpointInventory` and
      # `forwardingOut`; passing that whole result makes `network.data` a
      # non-site shape and the schema rejects it (`expected attribute set`).
      cpmEnvelope =
        if builtins.isAttrs cpmForRenderer && builtins.isAttrs (cpmForRenderer.control_plane_model or null) then
          cpmForRenderer.control_plane_model
        else
          cpmForRenderer;
      artifactDigest = builtins.hashString "sha256" (builtins.toJSON cpmEnvelope);
      controlPlaneArtifact = {
        kind = "network-control-plane-artifact";
        artifactIdentity = artifactDigest;
        inherit artifactDigest;
        control_plane_model = cpmEnvelope;
        authorityConflicts = [ ];
        provenance = {
          producer = "nixos/${hostName}";
          source = "network-control-plane-model";
        };
      };
      bundle = networkRealizationModelInput.lib.realize {
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
    in
    {
      inherit bundle;
      cpm = cpmForRenderer;
    };

  # VM NIC platform binding, built from the host profile's vmNics list. Kept
  # here (FS-982-SMS-130) so the host profile passes platform-binding material
  # to the producer instead of assembling it inline.
  vmNicsPlatformBinding =
    { hostName, vmNics, bundle, target ? "nixos" }:
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
          // lib.optionalAttrs (nic.vhost or false) {
            # vhost-net / multiqueue request. The renderer turns this into
            # -netdev tap,...,vhost=on,queues=N + -device ...,mq=on,vectors=N
            # because qemu rejects vhost/queues inside -nic and -netdev bridge.
            vhost = true;
          }
          // lib.optionalAttrs (builtins.isInt (nic.queues or null)) {
            inherit (nic) queues;
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
          inherit target;
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
    realizeAll
    realizeBundle
    realizeInventory
    vmNicsPlatformBinding
    ;
}
