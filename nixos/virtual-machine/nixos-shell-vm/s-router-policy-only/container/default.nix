{
  lib,
  pkgs,
  controlPlaneOut,
  ...
}:

let
  hostname = "s-router-policy-only";

  runtimeTargets = controlPlaneOut.control_plane_model.runtime.targets or { };

  runtimeTarget =
    if builtins.hasAttr hostname runtimeTargets then
      runtimeTargets.${hostname}
    else
      abort ''
        container/default.nix: runtime target '${hostname}' missing

        available runtime targets:
        ${builtins.toJSON (builtins.attrNames runtimeTargets)}

        full controlPlaneOut:
        ${builtins.toJSON controlPlaneOut}
      '';

  runtimeIfaces = runtimeTarget.effectiveRuntimeRealization.interfaces or { };
  runtimePorts = runtimeTarget.effectiveRuntimeRealization.runtimePorts or [ ];
  runtimeLogicalNode = runtimeTarget.logicalNode or { };

  endpointInventory = controlPlaneOut.endpointInventory or { };
  realization = endpointInventory.realization or { };
  realizationNodes = realization.nodes or { };

  realizedNode =
    if builtins.hasAttr hostname realizationNodes then
      realizationNodes.${hostname}
    else
      abort ''
        container/default.nix: realization node '${hostname}' missing

        available realization nodes:
        ${builtins.toJSON (builtins.attrNames realizationNodes)}

        endpointInventory:
        ${builtins.toJSON endpointInventory}
      '';

  realizedPorts = realizedNode.ports or { };

  enterpriseNames = builtins.attrNames (controlPlaneOut.enterprise or { });
  enterpriseName =
    if builtins.length enterpriseNames == 1 then
      builtins.elemAt enterpriseNames 0
    else
      abort ''
        container/default.nix: expected exactly one enterprise, got: ${lib.concatStringsSep ", " enterpriseNames}

        full controlPlaneOut:
        ${builtins.toJSON controlPlaneOut}
      '';

  siteNames = builtins.attrNames (controlPlaneOut.enterprise.${enterpriseName}.site or { });
  siteName =
    if builtins.length siteNames == 1 then
      builtins.elemAt siteNames 0
    else
      abort ''
        container/default.nix: expected exactly one site under enterprise '${enterpriseName}', got: ${lib.concatStringsSep ", " siteNames}

        enterprise subtree:
        ${builtins.toJSON controlPlaneOut.enterprise.${enterpriseName}}
      '';

  site = controlPlaneOut.enterprise.${enterpriseName}.site.${siteName};
  siteNodes = site.nodes or { };
  siteLinks = site.links or { };

  backingNodeName =
    if site ? policyNodeName then
      site.policyNodeName
    else
      abort ''
        container/default.nix: site.policyNodeName missing

        site:
        ${builtins.toJSON site}

        full controlPlaneOut:
        ${builtins.toJSON controlPlaneOut}
      '';

  backingNode =
    if builtins.hasAttr backingNodeName siteNodes then
      siteNodes.${backingNodeName}
    else
      abort ''
        container/default.nix: backing topology node '${backingNodeName}' missing from site.nodes

        site.nodes:
        ${builtins.toJSON siteNodes}

        site:
        ${builtins.toJSON site}
      '';

  upstreamSelectorNodeName =
    if site ? upstreamSelectorNodeName then
      site.upstreamSelectorNodeName
    else
      null;

  upstreamSelectorNode =
    if upstreamSelectorNodeName != null && builtins.hasAttr upstreamSelectorNodeName siteNodes then
      siteNodes.${upstreamSelectorNodeName}
    else
      null;

  topoIfaceForRuntime = import ../lib/renderer/topology.nix {
    inherit
      lib
      hostname
      runtimeTarget
      backingNodeName
      backingNode
      realizedPorts
      runtimePorts
      siteLinks
      controlPlaneOut
      ;
  };

  topoDetails =
    map
      (name: topoIfaceForRuntime name runtimeIfaces.${name})
      (lib.sort builtins.lessThan (builtins.attrNames runtimeIfaces));

  mkNetwork = import ../lib/renderer/network.nix { inherit lib; };

  renderedNetworks = builtins.listToAttrs (map mkNetwork topoDetails);

  debugArtifacts = {
    "network-artifacts/container-control-plane-out.json".text =
      builtins.toJSON controlPlaneOut;

    "network-artifacts/container-endpoint-inventory.json".text =
      builtins.toJSON endpointInventory;

    "network-artifacts/container-runtime-target.json".text =
      builtins.toJSON runtimeTarget;

    "network-artifacts/container-runtime-logical-node.json".text =
      builtins.toJSON runtimeLogicalNode;

    "network-artifacts/container-runtime-interfaces.json".text =
      builtins.toJSON runtimeIfaces;

    "network-artifacts/container-runtime-ports.json".text =
      builtins.toJSON runtimePorts;

    "network-artifacts/container-realized-node.json".text =
      builtins.toJSON realizedNode;

    "network-artifacts/container-realized-ports.json".text =
      builtins.toJSON realizedPorts;

    "network-artifacts/container-site.json".text =
      builtins.toJSON site;

    "network-artifacts/container-site-nodes.json".text =
      builtins.toJSON siteNodes;

    "network-artifacts/container-site-links.json".text =
      builtins.toJSON siteLinks;

    "network-artifacts/container-backing-node-name".text =
      backingNodeName;

    "network-artifacts/container-backing-node.json".text =
      builtins.toJSON backingNode;

    "network-artifacts/container-upstream-selector-node-name".text =
      if upstreamSelectorNodeName == null then "" else upstreamSelectorNodeName;

    "network-artifacts/container-upstream-selector-node.json".text =
      builtins.toJSON upstreamSelectorNode;

    "network-artifacts/container-topology-details.json".text =
      builtins.toJSON topoDetails;

    "network-artifacts/container-rendered-networks.json".text =
      builtins.toJSON renderedNetworks;
  };
in
{
  imports = [
    ./debugging-packages.nix
  ];

  networking.hostName = hostname;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.networkmanager.enable = false;
  networking.useHostResolvConf = false;

  networking.firewall.enable = false;
  services.resolved.enable = false;

  boot.isContainer = true;

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = lib.mkDefault 1;
    "net.ipv6.conf.all.forwarding" = lib.mkDefault 1;
    "net.ipv6.conf.default.forwarding" = lib.mkDefault 1;
  };

  systemd.network.networks = lib.mkForce renderedNetworks;

  environment.etc = lib.mkMerge [
    debugArtifacts
  ];

  system.activationScripts.networkArtifactsDebug = lib.stringAfter [ "etc" ] ''
    mkdir -p /etc/network-artifacts
    cp -f ${pkgs.writeText "container-control-plane-out.json" (builtins.toJSON controlPlaneOut)} /etc/network-artifacts/container-control-plane-out.json
    cp -f ${pkgs.writeText "container-endpoint-inventory.json" (builtins.toJSON endpointInventory)} /etc/network-artifacts/container-endpoint-inventory.json
    cp -f ${pkgs.writeText "container-runtime-target.json" (builtins.toJSON runtimeTarget)} /etc/network-artifacts/container-runtime-target.json
    cp -f ${pkgs.writeText "container-runtime-logical-node.json" (builtins.toJSON runtimeLogicalNode)} /etc/network-artifacts/container-runtime-logical-node.json
    cp -f ${pkgs.writeText "container-runtime-interfaces.json" (builtins.toJSON runtimeIfaces)} /etc/network-artifacts/container-runtime-interfaces.json
    cp -f ${pkgs.writeText "container-runtime-ports.json" (builtins.toJSON runtimePorts)} /etc/network-artifacts/container-runtime-ports.json
    cp -f ${pkgs.writeText "container-realized-node.json" (builtins.toJSON realizedNode)} /etc/network-artifacts/container-realized-node.json
    cp -f ${pkgs.writeText "container-realized-ports.json" (builtins.toJSON realizedPorts)} /etc/network-artifacts/container-realized-ports.json
    cp -f ${pkgs.writeText "container-site.json" (builtins.toJSON site)} /etc/network-artifacts/container-site.json
    cp -f ${pkgs.writeText "container-site-nodes.json" (builtins.toJSON siteNodes)} /etc/network-artifacts/container-site-nodes.json
    cp -f ${pkgs.writeText "container-site-links.json" (builtins.toJSON siteLinks)} /etc/network-artifacts/container-site-links.json
    cp -f ${pkgs.writeText "container-backing-node-name" backingNodeName} /etc/network-artifacts/container-backing-node-name
    cp -f ${pkgs.writeText "container-backing-node.json" (builtins.toJSON backingNode)} /etc/network-artifacts/container-backing-node.json
    cp -f ${pkgs.writeText "container-upstream-selector-node-name" (if upstreamSelectorNodeName == null then "" else upstreamSelectorNodeName)} /etc/network-artifacts/container-upstream-selector-node-name
    cp -f ${pkgs.writeText "container-upstream-selector-node.json" (builtins.toJSON upstreamSelectorNode)} /etc/network-artifacts/container-upstream-selector-node.json
    cp -f ${pkgs.writeText "container-topology-details.json" (builtins.toJSON topoDetails)} /etc/network-artifacts/container-topology-details.json
    cp -f ${pkgs.writeText "container-rendered-networks.json" (builtins.toJSON renderedNetworks)} /etc/network-artifacts/container-rendered-networks.json
  '';

  system.stateVersion = "25.11";
}
