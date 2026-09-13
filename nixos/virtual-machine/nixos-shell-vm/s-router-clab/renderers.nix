{ inputs
, lib
, relativeRepo
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

  # FS-982: the host profile imports renderer output; bundle production lives
  # behind the producer boundary, not in the host profile.
  producer = import (relativeRepo.module "library/10-vms/nixos-shell-vm/renderer-pipeline-producer.nix") {
    inherit lib;
  };

  inventory = import inventoryPath;

  realized = producer.realizeAll {
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

  canonicalBundle = realized.bundle;

  rendererInput = {
    inherit hostName;
    bundle = canonicalBundle;
    # Management VLAN from CPM deployment hosts (URS: inventory -> CPM -> renderer)
    managementVlan =
      let
        hostDeploy =
          if realized.cpm ? deploymentHosts then realized.cpm.deploymentHosts.${hostName} or null else null;
      in
      if hostDeploy != null && hostDeploy ? uplinks then hostDeploy.uplinks.management or null else null;
    rendererInventoryJsonPath = builtins.toFile "renderer-inventory-${hostName}.json"
      (builtins.toJSON inventory);
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
in
{
  imports = [
    render-clab
    render-nebula
    render-wireguard
    sops
  ];
}
