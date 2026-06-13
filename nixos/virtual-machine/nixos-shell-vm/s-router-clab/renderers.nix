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
  sops = "${labPath}/sops-routing-${hostName}.nix";

  cpmLib = inputs.network-control-plane-model.libBySystem.${system};

  cpmBuilt = cpmLib.compileAndBuildFromPaths {
    inputPath = "${labPath}/intent.nix";
    inventoryPath = "${labPath}/inventory-clab.nix";
  };

  rendererInput = {
    inherit hostName;
    cpm = cpmBuilt;
    controlPlane = cpmBuilt;
    # Management VLAN from CPM deployment hosts (URS: inventory → CPM → renderer)
    managementVlan =
      let
        hostDeploy = if cpmBuilt ? deploymentHosts then cpmBuilt.deploymentHosts.${hostName} or null else null;
      in
        if hostDeploy != null && hostDeploy ? uplinks then hostDeploy.uplinks.management or null else null;
    # CPM_GAP: CPM does not yet emit bridgeControl for host-level bridges.
    bridgeControl = {
      dhcpServer = false;
      masquerade = "both";
    };
  };

  render-clab =
    inputs.network-renderer-containerlab-linux-backend.libBySystem.${system}.renderer.hostModule (
      rendererInput
      // {
        inherit lib selectorFile;
      }
    );

  render-nebula =
    inputs.network-renderer-nebula.libBySystem.${system}.renderer.hostModule
      rendererInput;

  render-wireguard =
    inputs.network-renderer-wireguard.libBySystem.${system}.renderer.hostModule
      rendererInput;

  renderer-contract = {
    inherit render-clab render-nebula render-wireguard;
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
