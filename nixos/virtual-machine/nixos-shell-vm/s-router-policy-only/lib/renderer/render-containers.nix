# ./lib/renderer/render-containers.nix
{
  lib,
  inventory,
  nodeName,
  hostName,
  cpm ? null,
}:

let
  validated = import ./validate-realization.nix {
    inherit
      lib
      inventory
      nodeName
      hostName
      cpm
      ;
  };

  node = validated.realization.nodes.${nodeName};

  _hostMatch =
    if node.host != hostName then
      abort "renderer: node '${nodeName}' is assigned to host '${node.host}', not '${hostName}'"
    else
      true;

  ports = node.ports;

  bridgePorts = lib.filterAttrs (_: p: p.attach.kind == "bridge") ports;
in
{
  extraVeths = builtins.mapAttrs (_: p: {
    hostBridge = p.attach.bridge;
  }) bridgePorts;
}
