# network-* validation: current state and blockers

## Green

network-compiler, network-forwarding-model, network-labs,
network-realization-model, network-realization-schema, network-renderer-nebula,
network-renderer-wireguard, network-renderer-access-endpoint-nixos and
network-renderer-containerlab-linux-backend: latest CI run success.
nixos: `nix flake check --no-build` passes; the dispatched "Flake.lock: update
and push" run and the "Network model check" push run both succeed.

## Fixed in this work

FS-540 named-core DNS endpoints, requester-lane resolver reachability,
policy-lane and ingress policy-table defaults, overlay endpoint host identities
and overlay DNS ingress transit (control plane); tenant-set default attribution
(forwarding model); canonical route-table mapping (renderer); removal of the
obsolete nixos-network-compiler input and of brave in nixos; wrapped-CPM schema
validation (network-realization-schema 30e7372).

## Blocked

- network-control-plane-model: 13 pre-existing module/example migrations
  (FS-260-015, FS-310-120, FS-380-050, FS-410-030, FS-420-030, FS-460-050,
  FS-720-030, FS-740-010, FS-770-010, FS-800-010/012/030, FS-970-040) change
  modeled behavior or acceptance in specific FS areas; AGENTS requires the FS
  contract to move first and this engagement must not touch the URS/FS.
- network-renderer-nixos: 3 cases need an authoritative tri-site overlay example
  with a host inventory; the URS assigns intent to the user, and every
  derivation attempt from existing artifacts failed and was reverted.

Both are ownership/permission limits, not effort.
