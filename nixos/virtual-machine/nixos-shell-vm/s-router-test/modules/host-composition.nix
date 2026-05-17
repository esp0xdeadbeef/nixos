{ inputs
, lib
, outPath
, pkgs
, ...
}:

let
  api = inputs.network-renderer-nixos.lib;
  nebulaApi = inputs.network-renderer-nebula.libBySystem.x86_64-linux;

  identity = {
    enterpriseName = "esp0xdeadbeef";
    siteName = "nixos";
    boxName = "s-router-test";
  };

  fabric = {
    intentPath = "${inputs.network-labs}/labs/lab-s-sigma/s-router-test-three-site/intent.nix";
    inventoryPath = runtimeInventoryPath;
  };

  baseInventory = import "${inputs.network-labs}/labs/lab-s-sigma/s-router-test-three-site/getResolvedInventory.nix" {
    renderer = "nixos";
  };
  hetznerRuntime = import ../../../nixos-anywhere/s-router-hetzner-anywhere/runtime.nix;
  runtimeUnderlayEndpoints = [ ];
  addRuntimeUnderlayEndpoints =
    enterpriseSites:
    lib.mapAttrs
      (
        siteName: site:
          site
          // {
            overlays = lib.mapAttrs
              (
                overlayName: overlay:
                  overlay // { underlayEndpoints = lib.unique ((overlay.underlayEndpoints or [ ]) ++ runtimeUnderlayEndpoints); }
              )
              (site.overlays or { });
          }
      )
      enterpriseSites;
  runtimeInventory =
    baseInventory
    // {
      controlPlane = (baseInventory.controlPlane or { }) // {
        sites = lib.mapAttrs (_enterpriseName: addRuntimeUnderlayEndpoints) ((baseInventory.controlPlane or { }).sites or { });
      };
    };
  runtimeInventoryPath =
    builtins.toFile "s-router-test-runtime-inventory.nix" ''
      builtins.fromJSON ${builtins.toJSON (builtins.toJSON runtimeInventory)}
    '';

  sliceArgs = {
    inherit (identity) boxName;
    inherit (fabric) intentPath inventoryPath;
  };

  disabledContainers = { };
  clientRuntimeNodeNames = [
    "nas-node01"
    "printer-node01"
  ];

  commonContainerOptions = {
    autoStart = true;
    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
    ];
  };

  builtHost = api.renderer.buildHostFromPaths {
    inherit (fabric) intentPath inventoryPath;
    selector = identity.boxName;
    file = "nixos/virtual-machine/nixos-shell-vm/s-router-test/default.nix";
  };

  resolvedHostContext = (builtHost.hostContext or { }) // {
    hostname = identity.boxName;
  };

  renderedHost = api.host.build sliceArgs;

  renderedBridges = api.bridges.build sliceArgs;

  renderedContainers = api.containers.buildForBox (
    sliceArgs
    // {
      disabled = disabledContainers;
      defaults = commonContainerOptions;
    }
  );

  deploymentHostName =
    let
      fromBuiltHost =
        if
          builtHost ? hostContext
          && builtins.isAttrs builtHost.hostContext
          && builtHost.hostContext ? deploymentHostName
          && builtins.isString builtHost.hostContext.deploymentHostName
        then
          builtHost.hostContext.deploymentHostName
        else
          null;
    in
    if fromBuiltHost != null then fromBuiltHost else renderedHost.deploymentHostName or null;

  renderedHostNetworkBase = {
    hostName = renderedHost.hostName or identity.boxName;
    inherit deploymentHostName;
    bridgeNameMap = renderedBridges.bridgeNameMap or { };
    bridges = renderedBridges.bridges or { };
    sites = builtHost.renderedHost.sites or { };
    netdevs = (renderedHost.netdevs or { }) // (renderedBridges.netdevs or { });
    networks = (renderedHost.networks or { }) // (renderedBridges.networks or { });
    containers = renderedContainers;
    debug = {
      host = renderedHost.debug or { };
      bridges = renderedBridges.debug or { };
      containers = builtins.attrNames renderedContainers;
    };
  };

  nebulaRuntimePlan = nebulaApi.renderer.buildNebulaPlan {
    controlPlane = builtHost.controlPlaneOut or { };
    inventory = builtHost.globalInventory or { };
  };

  nebulaNodeBelongsToHost =
    _nodeName: node:
    let
      deploymentHost = (node.materialization or { }).deploymentHost or null;
    in
    !(builtins.isString deploymentHost) || deploymentHost == "" || deploymentHost == deploymentHostName;

  routerNebulaNodes =
    lib.filterAttrs
      nebulaNodeBelongsToHost
      (builtins.removeAttrs (nebulaRuntimePlan.nodes or { }) clientRuntimeNodeNames);

  realizationNodes = (((builtHost.globalInventory or { }).realization or { }).nodes or { });
  hetznerRealizationNodeFor = logicalName:
    let
      matches =
        lib.filterAttrs
          (
            _nodeName: node:
            (node.host or null) == "s-router-hetzner-anywhere"
            && ((node.logicalNode or { }).name or null) == logicalName
          )
          realizationNodes;
    in
      if matches == { } then
        throw "missing ${logicalName} realization node on s-router-hetzner-anywhere"
      else
        builtins.head (builtins.attrValues matches);
  runtimeContainerNameFor = logicalName:
    let
      node = hetznerRealizationNodeFor logicalName;
    in
      node.targetContainer or (node.runtimeName or logicalName);
  requireNebulaPlanNode = nodeName:
    if builtins.hasAttr nodeName (nebulaRuntimePlan.nodes or { }) then
      nodeName
    else
      throw "missing ${nodeName} in Nebula runtime plan";
  externalHetznerLighthouseName = requireNebulaPlanNode "hetz-router-lighthouse";
  externalHetznerNebulaCoreName = runtimeContainerNameFor "hetz-router-nebula-core";

  externalHetznerRuntimeNodeNames = [
    externalHetznerLighthouseName
    externalHetznerNebulaCoreName
  ];

  externalHetznerNebulaNodes =
    lib.filterAttrs
      (nodeName: _: builtins.elem nodeName externalHetznerRuntimeNodeNames)
      (nebulaRuntimePlan.nodes or { });

  routerNebulaRuntimePlan = nebulaRuntimePlan // {
    nodes = routerNebulaNodes;
    overlays = lib.mapAttrs
      (
        _overlayId: overlay:
          overlay
            // {
            runtimeNodes =
              if builtins.isAttrs (overlay.runtimeNodes or null) then
                lib.filterAttrs
                  (nodeName: _: builtins.hasAttr nodeName routerNebulaNodes)
                  (builtins.removeAttrs overlay.runtimeNodes clientRuntimeNodeNames)
              else
                overlay.runtimeNodes or { };
          }
      )
      (nebulaRuntimePlan.overlays or { });
  };

  bootstrapNebulaRuntimePlan = routerNebulaRuntimePlan // {
    nodes = routerNebulaNodes // externalHetznerNebulaNodes;
    overlays = lib.mapAttrs
      (
        _overlayId: overlay:
          overlay
          // {
            runtimeNodes =
              if builtins.isAttrs (overlay.runtimeNodes or null) then
                lib.filterAttrs
                  (nodeName: _: builtins.hasAttr nodeName (routerNebulaNodes // externalHetznerNebulaNodes))
                  (builtins.removeAttrs overlay.runtimeNodes clientRuntimeNodeNames)
              else
                overlay.runtimeNodes or { };
          }
      )
      (nebulaRuntimePlan.overlays or { });
  };

  controlPlaneData =
    if builtins.isAttrs (((builtHost.controlPlaneOut or { }).control_plane_model or { }).data or null) then
      (builtHost.controlPlaneOut.control_plane_model.data or { })
    else
      ((builtHost.controlPlaneOut or { }).data or { });

  controlPlaneRuntimeTargets =
    lib.foldlAttrs
      (
        enterpriseAcc: _enterpriseName: enterpriseSites:
          enterpriseAcc
          // lib.foldlAttrs
            (
              siteAcc: _siteName: siteData:
                siteAcc // (siteData.runtimeTargets or { })
            )
            { }
            enterpriseSites
      )
      { }
      controlPlaneData;

  secretNameFromPath =
    path:
    if builtins.isString path && lib.hasPrefix "/run/secrets/" path then
      lib.removePrefix "/run/secrets/" path
    else
      "";

  routedPrefixSecretNamesForTarget =
    target:
    lib.concatMap
      (advertisement:
        let
          delegatedPrefix =
            if builtins.isAttrs (advertisement.delegatedPrefix or null) then
              advertisement.delegatedPrefix
            else
              { };
        in
        [ (secretNameFromPath (delegatedPrefix.sourceFile or "")) ])
      ((target.advertisements or { }).ipv6Ra or [ ]);

  hetznerAccessPrefixSecretNames =
    lib.sort builtins.lessThan (
      lib.unique (
        lib.filter
          (name: builtins.isString name && name != "")
          (
            lib.mapAttrsToList
              (_targetName: target: (target.externalValidation or { }).delegatedPrefixSecretName or "")
              controlPlaneRuntimeTargets
            ++ lib.concatLists (lib.mapAttrsToList (_targetName: routedPrefixSecretNamesForTarget) controlPlaneRuntimeTargets)
          )
      )
    );

  hetznerAccessNodeNames =
    builtins.map
      (secretName: lib.removePrefix "access-node-ipv6-prefix-" secretName)
      hetznerAccessPrefixSecretNames;

  renderedHostNetwork = renderedHostNetworkBase // {
    overlayRuntime = {
      nebula = routerNebulaRuntimePlan;
    };
  };

  builders = import ./container-builders.nix {
    inherit lib pkgs;
    mkNebulaRuntimeService = nodeName:
      nebulaApi.renderer.buildNebulaRuntimeNixosModule {
        inherit pkgs nodeName;
        runtimeNode = routerNebulaRuntimePlan.nodes.${nodeName};
      };
  };

  overlayContainers = import ./overlay-containers.nix {
    inherit lib renderedContainers;
    nebulaRuntimePlan = routerNebulaRuntimePlan;
    inherit (builders) mkNebulaNode mkNebulaProfileMount mkNebulaRuntimeAddon;
  };

  hostileGuaOverrides = import ./hostile-gua-overrides.nix {
    inherit lib renderedContainers hetznerAccessPrefixSecretNames;
  };

in
{
  imports = [
    (builtHost.artifactModule or { })
    (nebulaApi.renderer.buildNebulaBootstrapNixosModule {
      inherit pkgs;
      nebulaRuntimePlan = bootstrapNebulaRuntimePlan;
      externalLighthousePublicIpv4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
      externalLighthousePublicIpv6SecretPath = "/run/secrets/hetzner-public-ipv6";
      externalPortForwardPublicIpv4SecretPath = "/run/secrets/hetzner-public-ipv4";
      externalPortForwardPublicIpv6SecretPath = "/run/secrets/hetzner-public-ipv6";
      externalPortForwardNodeNames = [ ];
      externalRuntimeNodeNames = [ externalHetznerNebulaCoreName ];
      runtimeListenHosts = {
        ${externalHetznerNebulaCoreName} = "172.31.254.4";
      };
      externalRemoteLighthouseEndpoint4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
      externalRemoteLighthouseEndpoint6 = "";
      externalSuppressPublicLighthouseStaticMap = true;
      sopsProfileSecretPrefix = "nebula-profile";
    })
  ];

  system.stateVersion = lib.mkForce "25.11";

  environment.systemPackages = with pkgs; [
    bindfs
    gron
    ethtool
    iproute2
    iputils
    jq
    lsof
    mtr
    nftables
    nebula
    openssh
    procps
    ripgrep
    strace
    tcpdump
    traceroute
  ];

  _module.args = {
    inherit identity fabric;
    globalInventory = builtHost.globalInventory or { };
    hostContext = resolvedHostContext;
    intent = builtHost.fabricInputs or { };
    fabricInputs = builtHost.fabricInputs or { };
    compilerOut = builtHost.compilerOut or { };
    forwardingOut = builtHost.forwardingOut or { };
    controlPlaneOut = builtHost.controlPlaneOut or { };
    inherit renderedHostNetwork;
    inherit hetznerAccessNodeNames hetznerAccessPrefixSecretNames;
  };

  environment.etc."network-renderer/network-renderer-nebula.json".text = builtins.toJSON {
    overlays = builtins.attrNames (routerNebulaRuntimePlan.overlays or { });
    nodes = builtins.attrNames (routerNebulaRuntimePlan.nodes or { });
  };

  environment.etc."s-router-test/hetzner-access-ipv6-nodes".text =
    lib.concatLines hetznerAccessNodeNames;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.wait-online.enable = false;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = lib.mkForce false;
  systemd.network.netdevs = (renderedHost.netdevs or { }) // (renderedBridges.netdevs or { });

  # Management uplink (eth0.2 -> vlan2) should get DHCPv4 so the host itself
  # has connectivity. `mgmt` is a tenant L2 bridge (VLAN 330), not the host mgmt
  # uplink; expect the host address on `vlan2` instead.
  systemd.network.networks =
    lib.recursiveUpdate ((renderedHost.networks or { }) // (renderedBridges.networks or { }))
      {
        "30-vlan2".networkConfig.DHCP = "ipv4";
      };

  containers = lib.foldl' lib.recursiveUpdate renderedContainers [
    hostileGuaOverrides
    overlayContainers
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];
  users.users.deadbeef.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];


}
