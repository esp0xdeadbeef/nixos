{
  lib,
  pkgs,
  controlPlaneOut,
  ...
}:

let
  hostname = "s-router-policy-only";

  listInvariants = import ../lib/list-invariants.nix { inherit lib; };
  inherit (listInvariants) duplicates;

  runtimeTargets = controlPlaneOut.control_plane_model.runtime.targets or { };

  runtimeTarget =
    if builtins.hasAttr hostname runtimeTargets then
      runtimeTargets.${hostname}
    else
      abort ''
        renderer/container/default.nix
        hostname: ${hostname}
        runtimeIfName: n/a
        linkName: n/a
        error: runtime target missing
      '';

  runtimeRealization =
    if runtimeTarget ? effectiveRuntimeRealization then
      runtimeTarget.effectiveRuntimeRealization
    else
      abort ''
        renderer/container/default.nix
        hostname: ${hostname}
        runtimeIfName: n/a
        linkName: n/a
        error: effectiveRuntimeRealization missing
      '';

  runtimeIfaces =
    if runtimeRealization ? interfaces then
      runtimeRealization.interfaces
    else
      abort ''
        renderer/container/default.nix
        hostname: ${hostname}
        runtimeIfName: n/a
        linkName: n/a
        error: runtime interfaces missing
      '';

  runtimePorts =
    if runtimeRealization ? runtimePorts then
      runtimeRealization.runtimePorts
    else
      abort ''
        renderer/container/default.nix
        hostname: ${hostname}
        runtimeIfName: n/a
        linkName: n/a
        error: runtimePorts missing
      '';

  runtimePortLinks = map (
    port:
    if port ? link then
      port.link
    else
      abort ''
        renderer/container/default.nix
        hostname: ${hostname}
        runtimeIfName: n/a
        linkName: n/a
        error: runtime port link missing
      ''
  ) runtimePorts;

  topoIfaceForRuntime = import ../lib/renderer/topology.nix {
    inherit
      lib
      hostname
      runtimeTarget
      runtimePorts
      ;
  };

  topoDetails =
    map
      (name: topoIfaceForRuntime name runtimeIfaces.${name})
      (lib.sort builtins.lessThan (builtins.attrNames runtimeIfaces));

  ifaceLinks = map (d: d.linkName) topoDetails;
  ifaceNames = map (d: d.renderedIfName) topoDetails;

  _uniqueRuntimeInterfaceLinks =
    let
      dup = duplicates ifaceLinks;
    in
    if dup != [ ] then
      abort ''
        renderer/container/default.nix
        hostname: ${hostname}
        runtimeIfName: n/a
        linkName: n/a
        error: duplicate runtime interface links
        duplicateLinks: ${builtins.toJSON dup}
      ''
    else
      true;

  _uniqueRuntimeInterfaceNames =
    let
      dup = duplicates ifaceNames;
    in
    if dup != [ ] then
      abort ''
        renderer/container/default.nix
        hostname: ${hostname}
        runtimeIfName: n/a
        linkName: n/a
        error: duplicate rendered interface names
        duplicateNames: ${builtins.toJSON dup}
      ''
    else
      true;

  _uniqueRuntimePortLinks =
    let
      dup = duplicates runtimePortLinks;
    in
    if dup != [ ] then
      abort ''
        renderer/container/default.nix
        hostname: ${hostname}
        runtimeIfName: n/a
        linkName: n/a
        error: duplicate runtime port links
        duplicateLinks: ${builtins.toJSON dup}
      ''
    else
      true;

  _linkCoverage =
    let
      missingLinks = lib.filter (linkName: !(builtins.elem linkName runtimePortLinks)) ifaceLinks;
      extraLinks = lib.filter (linkName: !(builtins.elem linkName ifaceLinks)) runtimePortLinks;
    in
    if missingLinks != [ ] || extraLinks != [ ] then
      abort ''
        renderer/container/default.nix
        hostname: ${hostname}
        runtimeIfName: n/a
        linkName: n/a
        error: runtime interface to runtime port link coverage mismatch
        missingLinks: ${builtins.toJSON missingLinks}
        extraLinks: ${builtins.toJSON extraLinks}
      ''
    else
      true;

  mkNetwork = import ../lib/renderer/network.nix { inherit lib; };

  renderedNetworks = builtins.listToAttrs (map mkNetwork topoDetails);

  rendererDebug = controlPlaneOut.rendererDebug or false;

  debugArtifacts = lib.mkMerge [
    {
      "network-artifacts/container-runtime-realization.json".text =
        builtins.toJSON runtimeRealization;

      "network-artifacts/container-rendered-networks.json".text =
        builtins.toJSON renderedNetworks;
    }

    (lib.optionalAttrs rendererDebug {
      "network-artifacts/container-control-plane-out.json".text =
        builtins.toJSON controlPlaneOut;

      "network-artifacts/container-topology-details.json".text =
        builtins.toJSON topoDetails;
    })
  ];
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
    cp -f ${pkgs.writeText "container-runtime-realization.json" (builtins.toJSON runtimeRealization)} /etc/network-artifacts/container-runtime-realization.json
    cp -f ${pkgs.writeText "container-rendered-networks.json" (builtins.toJSON renderedNetworks)} /etc/network-artifacts/container-rendered-networks.json
    ${lib.optionalString rendererDebug ''
      cp -f ${pkgs.writeText "container-control-plane-out.json" (builtins.toJSON controlPlaneOut)} /etc/network-artifacts/container-control-plane-out.json
      cp -f ${pkgs.writeText "container-topology-details.json" (builtins.toJSON topoDetails)} /etc/network-artifacts/container-topology-details.json
    ''}
  '';

  system.stateVersion = "25.11";
}
