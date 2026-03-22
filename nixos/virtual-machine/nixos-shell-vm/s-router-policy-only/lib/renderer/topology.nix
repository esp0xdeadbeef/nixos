{
  lib,
  hostname,
  runtimeTarget,
  backingNodeName,
  backingNode,
  realizedPorts,
  runtimePorts ? [ ],
  siteLinks ? { },
  controlPlaneOut ? null,
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  selectUnique =
    what: candidates: details:
    let
      count = builtins.length candidates;
    in
    if count == 1 then
      builtins.elemAt candidates 0
    else if count == 0 then
      abort ''
        lib/renderer/topology.nix: no ${what}

        ${details}
      ''
    else
      abort ''
        lib/renderer/topology.nix: ambiguous ${what}: ${lib.concatStringsSep ", " candidates}

        ${details}
      '';

  realizedInterfaceNamesFor =
    matches:
    lib.unique (
      lib.filter (name: name != null && name != "") (
        map (
          portName:
          let
            port = matches.${portName};
          in
          if port ? interface && port.interface ? name then
            port.interface.name
          else
            null
        ) (sortedAttrNames matches)
      )
    );

  preferredBackingIfaceNames =
    preferredNames: matches:
    lib.filter (name: builtins.elem name preferredNames) (sortedAttrNames matches);

  preferredRealizedPortNames =
    preferredInterfaceNames: matches:
    lib.filter (
      portName:
      let
        port = matches.${portName};
      in
      port ? interface
      && port.interface ? name
      && builtins.elem port.interface.name preferredInterfaceNames
    ) (sortedAttrNames matches);
in
runtimeIfName: runtimeIf:
let
  linkName =
    if runtimeIf ? link then
      runtimeIf.link
    else
      abort ''
        lib/renderer/topology.nix: runtime interface '${runtimeIfName}' has no link

        runtime interface:
        ${builtins.toJSON runtimeIf}

        runtime target:
        ${builtins.toJSON runtimeTarget}
      '';

  backingMatches =
    lib.filterAttrs (_: v: (v.link or null) == linkName) (backingNode.interfaces or { });

  realizedMatches =
    lib.filterAttrs (_: p: (p.link or null) == linkName) realizedPorts;

  preferredInterfaceNames =
    lib.unique (
      lib.filter (name: name != null && name != "") (
        (realizedInterfaceNamesFor realizedMatches)
        ++ [
          (if runtimeIf ? runtimeInterface then runtimeIf.runtimeInterface else null)
          runtimeIfName
        ]
      )
    );

  backingIfaceCandidates = sortedAttrNames backingMatches;
  narrowedBackingIfaceCandidates = preferredBackingIfaceNames preferredInterfaceNames backingMatches;

  backingIfaceName =
    if builtins.length backingIfaceCandidates == 1 then
      builtins.elemAt backingIfaceCandidates 0
    else
      selectUnique
        "backing interface on topology node '${backingNodeName}' for link '${linkName}'"
        narrowedBackingIfaceCandidates
        ''
          runtime interface:
          ${builtins.toJSON runtimeIf}

          runtime target:
          ${builtins.toJSON runtimeTarget}

          preferred interface names:
          ${builtins.toJSON preferredInterfaceNames}

          matching backing interfaces:
          ${builtins.toJSON backingIfaceCandidates}

          runtime ports:
          ${builtins.toJSON runtimePorts}

          backing node:
          ${builtins.toJSON backingNode}

          site links:
          ${builtins.toJSON siteLinks}

          full controlPlaneOut:
          ${builtins.toJSON controlPlaneOut}
        '';

  backingIface = backingMatches.${backingIfaceName};

  realizedPortCandidates = sortedAttrNames realizedMatches;
  narrowedRealizedPortCandidates =
    preferredRealizedPortNames (lib.unique ([ backingIfaceName ] ++ preferredInterfaceNames)) realizedMatches;

  realizedPortName =
    if builtins.length realizedPortCandidates == 1 then
      builtins.elemAt realizedPortCandidates 0
    else
      selectUnique
        "realized port on '${hostname}' for link '${linkName}'"
        narrowedRealizedPortCandidates
        ''
          runtime interface:
          ${builtins.toJSON runtimeIf}

          runtime target:
          ${builtins.toJSON runtimeTarget}

          preferred interface names:
          ${builtins.toJSON (lib.unique ([ backingIfaceName ] ++ preferredInterfaceNames))}

          matching realized ports:
          ${builtins.toJSON realizedPortCandidates}

          runtime ports:
          ${builtins.toJSON runtimePorts}

          realized ports:
          ${builtins.toJSON realizedPorts}
        '';

  realizedPort = realizedMatches.${realizedPortName};

  renderedIfName =
    if realizedPort ? interface && realizedPort.interface ? name then
      realizedPort.interface.name
    else if runtimeIf ? runtimeInterface then
      runtimeIf.runtimeInterface
    else
      runtimeIfName;
in
{
  inherit
    runtimeIfName
    renderedIfName
    linkName
    backingIfaceName
    backingIface
    realizedPortName
    realizedPort
    ;
}
