# network-* CI validation status

Verified state of the `~/github/network-*` check suites, the fixes landed this
run, and the one remaining contract gap that blocks the rest.

## Verified green (GitHub Actions)

| repo | commit | result |
| --- | --- | --- |
| network-compiler | `27080ef` | success |
| network-forwarding-model | `ec16160` | success (81/81) |
| network-labs | `3a710c36` | success (42/0) |
| network-realization-model | `b6ab76a` | success (`nix flake check`) |
| network-realization-schema | `6881bff` | success (`nix flake check`) |
| network-access-endpoint | `01de9c3` | success |
| network-renderer-nebula | `7054765` | success (15/15) |
| network-renderer-wireguard | `dc39a38` | success (PR #1) |
| network-renderer-containerlab-linux-backend | `f90dc63` | success (full suite) |

## Fixed this run (network-control-plane-model)

- `64ec24f`: named-core DNS listener/forwarder is the relation's emitted terminal
  attachment endpoint, never the resolver loopback (FS-540-HDS-010-SDS-010-SMS-020
  "An ownership loopback is not a substitute"; SMS-035 "a node loopback ... shall
  not be substituted"). FS-540-010/020/025/030/035/040/045 green in CI.
- `7a4a1c6`: FS-525 named-core and egress cases assert the emitted endpoint and
  the declared `egressSurface` determinism.
- `f7903c9`: requester-lane resolver endpoint reachability. SMS-020 requires
  "relation-owned requester-lane route authority containing policy table,
  outgoing lane, selected next-hop identity, and provenance for each requested
  family and resolver endpoint prefix", and SMS-040 defines its keying. The
  control plane is the owning writer: the admitted relation, the resolver
  endpoint, the requester access lane and the lane next hop are all modelled
  inputs, so emitting the requester leg materializes existing authority (URS
  "Only modeled authority can create network behavior") and does not re-derive
  upstream meaning (FS-171). It is emitted only on admitted downstream access
  lanes, never on exit/uplink lanes (FS-550), never fanned out to unadmitted
  siblings (SMS-040), and deduplicated against the destination pass (FS-315).
  `test-dns-service-policy-routes`, `test-runtime-origin-loopback-egress` and
  `test-network-labs-inventory-sweep` (21 outputs) pass; CPM suite 224 PASS with
  the same 18 pre-existing reds as `64ec24f^`.

The earlier claim that this requester lane "violates FS-171" was wrong and is
retracted: both the URS layer-ownership rules and FS-171 assign the
realization-of-modelled-authority case to the layer that writes the canonical
target routes, which is the control plane, not the forwarding model.

## Remaining contract gap (BLOCKED)

`test-preferred-uplink-defaults` (and the four sibling cases below) needs the
policy point's access-uplink lane to carry the per-family default of the exit
the access scope selected.

Evidence (compiled `s-router-overlay-dns-lane-policy`, inventory-nixos):

    policy      p2p-...--access-s-router-access-client--uplink-isp-a  v4d=0 v6d=0
    upstream    p2p-...--access-s-router-access-client--uplink-isp-a  v4d=2 v6d=2

The forwarding model places the access-selected defaults on the upstream
selector's side of the lane. The policy point, where the selection becomes a
policy table, has none. `normalize-runtime-routes.nix` already complements
policy-lane routes from a peer interface, but that complement is gated on
`isUpstreamSelectorCoreDefaultInterface`, i.e. it only accepts core-facing
default interfaces; a selector access lane is not one. A policy target sees only
its own interfaces, so it cannot see the peer lane's default at all.

Closing this needs a forwarding-model output (the per-lane selected default
bound to the policy-facing end of the lane) and the matching FS text for that
output. Per AGENTS, the owning requirement must be fixed in URS/FS first, in the
same change, and the authoritative GAMP set lives in `network-codex-agent`,
which this run was instructed to skip ("codex-agent can be skipped"). Producing
the default by inference in the control plane would synthesize a next hop the
model did not declare (FS-315) and is therefore not an acceptable workaround.

Same chain: `test-sitec-overlay-service-ingress`,
`test-s-router-hetz-overlay-dns-ingress`,
`test-example-overlay-upstream-policy-defaults-preserved`,
`FS-460-HDS-010-SDS-010-SMS-050`.

Other pre-existing reds (`FS-260-015`, `FS-310-120`, `FS-380-050`, `FS-410-030`,
`FS-420-030`, `FS-500-040`, `FS-720-030`, `FS-740-010`, `FS-770-010`,
`FS-800-010/012/030`, `FS-970-040`) and the five `network-renderer-nixos` reds
are module/example migrations that reproduce on the pre-change revisions.

Unblock: permission to edit `network-codex-agent` GAMP plus the
forwarding-model lane-default emission, or confirmation that the policy-facing
lane default is already emitted upstream and merely unconsumed.
