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
    rendererInventoryJsonPath = builtins.toFile "renderer-inventory-${hostName}.json"
      (builtins.toJSON (import inventoryPath));
    # CPM_GAP: CPM does not yet emit bridgeControl for host-level bridges.
    bridgeControl = {
      dhcpServer = false;
      masquerade = "both";
    };
  };

  render-clab =
    { lib, pkgs, ... }:
    {
      _module.args.clabDeploymentHost = rendererInput.hostName;
      _module.args.clabCpmJsonPath =
        builtins.toFile
          "cpm-${rendererInput.hostName}.json"
          (builtins.toJSON rendererInput.cpm);
      _module.args.clabRendererInventoryJsonPath = rendererInput.rendererInventoryJsonPath;
      _module.args.containerlabLinuxRendererSelf = builtins.path {
        path = inputs.network-renderer-containerlab-linux-backend;
        name = "network-renderer-containerlab-linux-backend";
      };
      _module.args.containerlabLinuxGenerateClabConfig =
        inputs.network-renderer-containerlab-linux-backend.packages.${pkgs.stdenv.hostPlatform.system}.generate-clab-config;
      _module.args.containerlabLinuxRendererInput =
        builtins.removeAttrs rendererInput [
          "cpm"
          "controlPlane"
          "cpmJsonPath"
          "deploymentHost"
          "rendererInventoryJsonPath"
        ];

      assertions = [
        {
          assertion = rendererInput ? hostName;
          message = "containerlab linux renderer input must include hostName";
        }
      ];

      networking.hostName = lib.mkDefault rendererInput.hostName;

      imports = [
        "${inputs.network-renderer-containerlab-linux-backend}/host-module.nix"
      ];
    };

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
