{ inputs
, lib
, relativeRepo
, labSource
, selectorFile
, system
, hostName ? "s-router-nixos"
, vmNics ? [ ]
,
}:

{ config, ... }:

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

  # FS-982-SMS-130: the VM NIC platform binding is produced by the producer
  # boundary from the host profile's vmNics list.
  # The host's own deployment facts, from the inventory this render is built from:
  # eth0's bridge networks and uplinks, the management VLAN among them. A
  # container-hosted router has no VM NICs, so without these the binding is null and
  # the renderer has no uplink facts at all (no vlan2, no eth0.2).
  deploymentHosts =
    if builtins.isAttrs (inventory.deployment or null) && builtins.isAttrs (inventory.deployment.hosts or null)
    then inventory.deployment.hosts
    else { };

  platformBinding = producer.vmNicsPlatformBinding {
    inherit hostName vmNics deploymentHosts;
    bundle = canonicalBundle;
  };

  # vhost NICs render as `-netdev tap,ifname=tap-<nicId>,vhost=on`, which qemu
  # does NOT bridge itself, so the host must enslave the tap. Derive the exact
  # pairs from the same platform binding the renderer consumes.
  vhostTapAttachments =
    if platformBinding == null then
      [ ]
    else
      let
        target = platformBinding.categories.deployment.vmTargets.${hostName} or null;
        nics =
          if builtins.isAttrs target && builtins.isList (target.nics or null) then target.nics else [ ];
      in
      map
        (nic: {
          tap = "tap-${nic.nicId}";
          bridge = nic.attachment.name;
        })
        (builtins.filter (nic: (nic.vhost or false) == true) nics);

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
      // lib.optionalAttrs (platformBinding != null) {
        inherit platformBinding;
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
      vhostTapAttachments
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
