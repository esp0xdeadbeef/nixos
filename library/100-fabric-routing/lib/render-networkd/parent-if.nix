{ lib }:

{ utils }:

all: nodeName: carrier:

let
  candidates = [
    (all.topologyRaw.nodes.${nodeName}.ifs.${carrier} or null)
    (all.topology.nodes.${nodeName}.ifs.${carrier} or null)
    (all.nodes.${nodeName}.ifs.${carrier} or null)
  ];

  resolved = utils.firstNonNull candidates;
in
if resolved == null then
  throw "render-networkd: missing parent if for carrier='${carrier}' on node='${nodeName}'"
else
  resolved
