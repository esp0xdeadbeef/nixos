{ inputs
, lib
, pkgs
, selector
, file
, inventoryRenderer ? "nixos"
, deploymentHostName ? null
, hostedPeerHostName ? "s-router-hetzner-anywhere"
, enableNebulaRenderer ? true
, excludedNebulaNodeNames ? [
    "nas-node01"
    "printer-node01"
  ]
,
}:
let
  nixosRenderer = inputs.network-renderer-nixos.lib.renderer;
  nebulaRenderer =
    if enableNebulaRenderer then
      inputs.network-renderer-nebula.libBySystem.x86_64-linux.renderer
    else
      null;
  inventoryPath =
    builtins.toFile "s-router-${inventoryRenderer}-inventory.nix" ''
      import ${inputs.network-labs}/labs/lab-s-sigma/s-router-test-three-site/getResolvedInventory.nix { renderer = "${inventoryRenderer}"; }
    '';
  fabric = {
    intentPath = "${inputs.network-labs}/labs/lab-s-sigma/s-router-test-three-site/intent.nix";
    inherit inventoryPath;
  };
  builtHost = nixosRenderer.buildHostFromPaths {
    inherit (fabric) intentPath inventoryPath;
    inherit selector file;
    containerDefaults = {
      autoStart = true;
      additionalCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };
    disabled = { };
  };
  renderedHost = builtHost.renderedHost or { };
  renderedContainers = renderedHost.containers or { };
  resolvedDeploymentHostName =
    if builtins.isString deploymentHostName then deploymentHostName
    else if builtins.isString ((builtHost.hostContext or { }).deploymentHostName or null) then builtHost.hostContext.deploymentHostName
    else renderedHost.deploymentHostName or null;
  emptyNebulaRuntimePlan = {
    overlays = { };
    nodes = { };
  };
  nebulaRuntimePlan =
    if enableNebulaRenderer then
      nebulaRenderer.buildNebulaPlan
        {
          controlPlane = builtHost.controlPlaneOut or { };
          inventory = builtHost.globalInventory or { };
        }
    else
      emptyNebulaRuntimePlan;
  hostedPeerPlan =
    if enableNebulaRenderer then
      nebulaRenderer.selectHostedNebulaRuntimePlan
        {
          inherit nebulaRuntimePlan;
          inventory = builtHost.globalInventory or { };
          hostName = hostedPeerHostName;
        }
    else
      emptyNebulaRuntimePlan;
  localPlan =
    if enableNebulaRenderer then
      nebulaRenderer.selectDeploymentNebulaRuntimePlan
        {
          inherit nebulaRuntimePlan;
          deploymentHostName = resolvedDeploymentHostName;
          excludedNodeNames = excludedNebulaNodeNames;
        }
    else
      emptyNebulaRuntimePlan;
  bootstrapPlan =
    if enableNebulaRenderer then
      nebulaRenderer.selectDeploymentNebulaRuntimePlan
        {
          inherit nebulaRuntimePlan;
          deploymentHostName = resolvedDeploymentHostName;
          excludedNodeNames = excludedNebulaNodeNames;
          extraNodeNames = builtins.attrNames (hostedPeerPlan.nodes or { });
        }
    else
      emptyNebulaRuntimePlan;
  runtimeContainerNameFor = logicalName:
    if enableNebulaRenderer then
      nebulaRenderer.runtimeContainerNameForHost
        {
          inventory = builtHost.globalInventory or { };
          hostName = hostedPeerHostName;
          inherit logicalName;
        }
    else
      logicalName;
  peerNebulaCoreName =
    if enableNebulaRenderer then
      runtimeContainerNameFor "hetz-router-nebula-core"
    else
      "";
  peerNebulaCoreNode =
    if builtins.hasAttr peerNebulaCoreName (localPlan.nodes or { }) then
      localPlan.nodes.${peerNebulaCoreName}
    else if builtins.hasAttr peerNebulaCoreName (hostedPeerPlan.nodes or { }) then
      hostedPeerPlan.nodes.${peerNebulaCoreName}
    else
      throw "s-router-model-host: ${peerNebulaCoreName} is missing from the selected Nebula runtime plans";
  peerNebulaCoreListenHost =
    if !enableNebulaRenderer then
      ""
    else if builtins.isString (peerNebulaCoreNode.service.listenHost or null) && peerNebulaCoreNode.service.listenHost != "" then
      peerNebulaCoreNode.service.listenHost
    else
      throw "s-router-model-host: ${peerNebulaCoreName}.service.listenHost must be provided by the model";
  delegatedPrefixSecretNames =
    let
      controlPlaneModel = (builtHost.controlPlaneOut or { }).control_plane_model or { };
      controlPlaneData = controlPlaneModel.data or (builtHost.controlPlaneOut.data or { });
      secretNameFromPath = path:
        if builtins.isString path && lib.hasPrefix "/run/secrets/" path then
          lib.removePrefix "/run/secrets/" path
        else
          "";
      namesForTarget = _targetName: target:
        builtins.map
          (advertisement:
            let
              delegatedPrefix = advertisement.delegatedPrefix or { };
            in
            secretNameFromPath (delegatedPrefix.sourceFile or ""))
          ((target.advertisements or { }).ipv6Ra or [ ]);
      siteRuntimeTargets = _enterpriseName: enterpriseSites:
        lib.concatLists (
          lib.mapAttrsToList (_siteName: siteData: lib.concatLists (lib.mapAttrsToList namesForTarget (siteData.runtimeTargets or { }))) enterpriseSites
        );
    in
    lib.sort builtins.lessThan (
      lib.unique (
        lib.filter (name: builtins.isString name && name != "") (
          lib.concatLists (lib.mapAttrsToList siteRuntimeTargets controlPlaneData)
        )
      )
    );
  builders =
    if enableNebulaRenderer then
      import ./nixos-shell-vm/s-router-test/modules/container-builders.nix
        {
          inherit lib pkgs;
          mkNebulaRuntimeService = nodeName: nebulaRenderer.buildNebulaRuntimeNixosModule {
            inherit pkgs nodeName;
            runtimeNode = localPlan.nodes.${nodeName};
            externalRemoteLighthouseEndpoint4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
            externalRemoteLighthouseEndpoint6SecretPath = "/run/secrets/hetzner-public-ipv6";
          };
        }
    else
      import ./nixos-shell-vm/s-router-test/modules/container-builders.nix {
        inherit lib pkgs;
        mkNebulaRuntimeService = _nodeName: { };
      };
  overlayContainers =
    if enableNebulaRenderer then
      import ./nixos-shell-vm/s-router-test/modules/overlay-containers.nix
        {
          inherit lib renderedContainers;
          nebulaRuntimePlan = localPlan;
          inherit (builders) mkNebulaNode mkNebulaProfileMount mkNebulaRuntimeAddon;
        }
    else
      { };
  bootstrapModule =
    if enableNebulaRenderer then
      import ./s-router-model-bootstrap.nix
        {
          inherit nebulaRenderer peerNebulaCoreName pkgs;
          plan = bootstrapPlan;
          runtimeListenHost = peerNebulaCoreListenHost;
        }
    else
      { };
in
{
  inherit builtHost fabric hostedPeerPlan localPlan nebulaRenderer nebulaRuntimePlan
    overlayContainers peerNebulaCoreName renderedContainers renderedHost resolvedDeploymentHostName
    bootstrapModule;
  peerNebulaCoreNode = peerNebulaCoreNode;
  accessNodeNames = builtins.map (lib.removePrefix "access-node-ipv6-prefix-") delegatedPrefixSecretNames;
  accessPrefixSecretNames = delegatedPrefixSecretNames;
}
