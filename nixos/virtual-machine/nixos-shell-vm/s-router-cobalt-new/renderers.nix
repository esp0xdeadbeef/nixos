{ inputs
, lib
, relativeRepo
, modelSource
, selectorFile
, system
, controlPlaneModelInput ? inputs.network-control-plane-model
, networkRealizationModelInput ? inputs.network-realization-model
, controlPlaneTransform ? cpm: cpm
, nixosRendererInput ? inputs.network-renderer-nixos
, wireguardRendererInput
, nebulaRendererInput ? inputs.network-renderer-nebula
, hostName ? "s-router-prod"
, inventoryFileName ? "inventory.nix"
, intentFileName ? "intent.nix"
, vmNics ? [ ]
,
}:

{ ... }:

let
  # Join with a PATH, not string interpolation: `"${modelSource}/..."` would
  # stringify the path, which copies it into the store and drops the store
  # context under pure evaluation (`nix flake check`).  `path + "/..."` keeps a
  # real path, which survives `import`/`readFile`.
  intentPath = modelSource + "/${intentFileName}";
  inventoryPath = modelSource + "/${inventoryFileName}";

  # FS-982: the host profile imports renderer output; bundle production lives
  # behind the producer boundary, not in the host profile. The inventory path
  # is passed as source selection; the producer resolves it (it may be a
  # { hostName }-arg function) and owns intent+inventory -> bundle.
  producer = import (relativeRepo.module "library/10-vms/nixos-shell-vm/renderer-pipeline-producer.nix") {
    inherit lib;
  };

  inventoryInput = import inventoryPath;
  inventory = producer.realizeInventory { inventoryInput = inventoryInput; inherit hostName; };

  # FS-982: realizeAll returns both the canonical bundle (for the NixOS and
  # WireGuard renderers) and the platform-neutral CPM output (so the Nebula
  # renderer, which consumes the CPM envelope, needs no second pipeline run).
  pipeline = producer.realizeAll {
    inherit
      system
      intentPath
      hostName
      controlPlaneTransform
      ;
    inventory = inventoryInput;
    controlPlaneModelInput = controlPlaneModelInput;
    networkRealizationModelInput = networkRealizationModelInput;
    rootLockIdentity = builtins.hashString "sha256" (builtins.readFile ../../../../flake.lock);
  };

  canonicalBundle = pipeline.bundle;

  rendererInput = {
    inherit hostName;
    bundle = canonicalBundle;
  };

  nebulaRendererInput' = rendererInput;

  # FS-982-SMS-130: the VM NIC platform binding is produced by the same
  # boundary, not assembled inline in the host profile.
  platformBinding = producer.vmNicsPlatformBinding {
    inherit hostName vmNics;
    bundle = canonicalBundle;
  };

  # FS-770-HDS-010: a container-hosted target needs the same host attachment a
  # VM NIC gets. With vmNics empty there is no VM binding, so supply the host
  # bridge per interface name instead (inventory fact: eth1 is the WAN uplink on
  # br-wan, the LAN side is the trunk bridge). The renderer applies this to every
  # rendered container and fails closed on a bridge the host does not render.
  containerBinding = {
    categories.deployment.containerTargets.${hostName} = {
      interfaceBridges = {
        wan = "br-wan";
        ens3 = "br-lan-trunk";
      };
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
      // lib.optionalAttrs (platformBinding == null) {
        platformBinding = containerBinding;
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

  # FS-460-HDS-010-SDS-010-SMS-010: a declared "nebula" overlay must be
  # realized by the Nebula renderer (persistent daemon + in-closure binary +
  # cert/profile secrets); otherwise the host emits an
  # s88-provider-interface-overlay-<name> unit that waits forever for a link
  # no daemon creates (silent fail-open). No-op when no Nebula overlay is
  # modeled.
  render-nebula =
    nebulaRendererInput.libBySystem.${system}.renderer.canonical.hostModule (
      nebulaRendererInput' // { inherit lib; }
    );

  providerContracts =
    let
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

in
{
  imports = [
    render-nixos
    render-wireguard
    render-nebula
  ];
}
