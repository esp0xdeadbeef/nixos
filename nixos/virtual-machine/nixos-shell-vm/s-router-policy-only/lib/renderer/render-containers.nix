{
  lib,
  inventory,
  nodeName,
  hostName,
  cpm ? null,
}:

let
  listInvariants = import ../list-invariants.nix { inherit lib; };
  inherit (listInvariants) duplicates;

  runtimeTargets = inventory.control_plane_model.runtime.targets or { };

  nodeRuntime =
    if lib.hasAttr nodeName runtimeTargets then
      runtimeTargets.${nodeName}.effectiveRuntimeRealization
    else
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: n/a
        linkName: n/a
        error: runtime target missing
        nodeName: ${nodeName}
      '';

  interfaces =
    if nodeRuntime ? interfaces then
      nodeRuntime.interfaces
    else
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: n/a
        linkName: n/a
        error: runtime interfaces missing
        nodeName: ${nodeName}
      '';

  interfaceNamesSorted = lib.sort builtins.lessThan (builtins.attrNames interfaces);

  interfaceEntries = map (
    runtimeIfName:
    {
      inherit runtimeIfName;
      runtimeIf = interfaces.${runtimeIfName};
    }
  ) interfaceNamesSorted;

  interfaceLinks = map (
    entry:
    let
      iface = entry.runtimeIf;
    in
    if iface ? link then
      iface.link
    else
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: ${entry.runtimeIfName}
        linkName: n/a
        error: runtime interface link missing
        nodeName: ${nodeName}
      ''
  ) interfaceEntries;

  _uniqueInterfaceNames =
    let
      dup = duplicates (map (entry: entry.runtimeIfName) interfaceEntries);
    in
    if dup != [ ] then
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: n/a
        linkName: n/a
        error: duplicate runtime interface names
        duplicateNames: ${builtins.toJSON dup}
        nodeName: ${nodeName}
      ''
    else
      true;

  _uniqueInterfaceLinks =
    let
      dup = duplicates interfaceLinks;
    in
    if dup != [ ] then
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: n/a
        linkName: n/a
        error: duplicate runtime interface links
        duplicateLinks: ${builtins.toJSON dup}
        nodeName: ${nodeName}
      ''
    else
      true;

  bridgeEntries = lib.filter (
    entry:
    let
      iface = entry.runtimeIf;
    in
    (iface.attachment.kind or null) == "bridge"
  ) interfaceEntries;

  bridgeLinks = map (entry: entry.runtimeIf.link) bridgeEntries;

  _uniqueBridgeLinks =
    let
      dup = duplicates bridgeLinks;
    in
    if dup != [ ] then
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: n/a
        linkName: n/a
        error: duplicate bridge-backed runtime interface links
        duplicateLinks: ${builtins.toJSON dup}
        nodeName: ${nodeName}
      ''
    else
      true;
in
{
  extraVeths = builtins.listToAttrs (
    map (
      entry:
      {
        name = entry.runtimeIfName;
        value = {
          hostBridge = entry.runtimeIf.attachment.bridge;
        };
      }
    ) bridgeEntries
  );
}
