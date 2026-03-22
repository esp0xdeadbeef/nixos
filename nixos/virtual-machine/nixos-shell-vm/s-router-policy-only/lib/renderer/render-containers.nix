# FILE: ./lib/renderer/render-containers.nix
{
  lib,
  inventory,
  nodeName,
  hostName,
  cpm ? null,
}:

let
  runtimeTargets = inventory.control_plane_model.runtime.targets or { };

  nodeRuntime =
    if lib.hasAttr nodeName runtimeTargets then
      runtimeTargets.${nodeName}.effectiveRuntimeRealization
    else
      abort "renderer: missing runtime target for node '${nodeName}'";

  interfaces = nodeRuntime.interfaces or { };

  bridgeIfs = lib.filterAttrs (_: v: (v.attachment.kind or null) == "bridge") interfaces;
in
{
  extraVeths = lib.mapAttrs' (
    ifName: v:
    lib.nameValuePair ifName {
      hostBridge = v.attachment.bridge;
    }
  ) bridgeIfs;
}
