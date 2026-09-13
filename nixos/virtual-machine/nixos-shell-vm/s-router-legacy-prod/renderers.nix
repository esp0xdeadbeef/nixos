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

  # FS-982: the host profile imports renderer output; bundle production lives
  # behind the producer boundary, not in the host profile. The inventory path
  # is passed as source selection; the producer resolves it (it may be a
  # { hostName }-arg function) and owns intent+inventory -> bundle.
  producer = import (relativeRepo.module "library/10-vms/nixos-shell-vm/renderer-pipeline-producer.nix") {
    inherit lib;
  };

  inventoryInput = import inventoryPath;
  inventory = producer.realizeInventory { inventoryInput = inventoryInput; inherit hostName; };

  canonicalBundle = producer.realizeBundle {
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

  rendererInput = {
    inherit hostName;
    bundle = canonicalBundle;
  };

  # FS-982-SMS-130: the VM NIC platform binding is produced by the same
  # boundary, not assembled inline in the host profile.
  platformBinding = producer.vmNicsPlatformBinding {
    inherit hostName vmNics;
    bundle = canonicalBundle;
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

  renderer-contract = {
    inherit canonicalBundle render-nixos;
    inherit inventory intentPath inventoryPath;
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
