{ lib
, nebulaRuntimePlan
, renderedContainers
, mkNebulaRuntimeAddon
, mkNebulaNode
, mkNebulaProfileMount
, excludedNodeNames ? [ ]
,
}:

let
  profiles = import ./overlay-profiles.nix { inherit lib; };
  augment = import ./overlay-augment.nix {
    inherit
      lib
      renderedContainers
      mkNebulaRuntimeAddon
      mkNebulaNode
      mkNebulaProfileMount
      ;
    profileForName = profiles.forName;
  };

  overlayNodeNames =
    lib.filter
      (nodeName: !(builtins.elem nodeName excludedNodeNames))
      (builtins.attrNames (nebulaRuntimePlan.nodes or { }));
in
lib.foldl'
  lib.recursiveUpdate
{ }
  (map
    (nodeName: augment.mkOverlayAugment nodeName (nebulaRuntimePlan.nodes.${nodeName}))
    overlayNodeNames)
