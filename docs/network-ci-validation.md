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

## Update: this run (FS-540/FS-550 control-plane work)

`network-control-plane-model`:
- `f7903c9` requester-lane resolver endpoint reachability (FS-540 SMS-020/040).
- `b93dc61`, `36237e7`, `ccf641b`, `45b313a` policy-lane selected-exit defaults
  complemented from the peer end of the modeled link, gated on the modeled
  runtime-origin source relation (FS-540 SMS-045, FS-550, FS-315), and the
  lane-less runtime-origin prefix removed from policy exit main tables.
- `adc93ea` blocker note updated.
- Full suite: 225 PASS / 17 FAIL; every remaining failure also fails on the
  pre-change revision.

`network-renderer-containerlab-linux-backend`: CI success (`f90dc63`).

`network-renderer-nixos`:
- `320bb23` maps the canonical route `table` field to systemd `Table` and drops
  the lane-less twin of a lane-assigned route (FS-315), which removes the
  runtime-origin prefix from policy exit main tables.
- `1381a05` client2 policy test migrated to the source-scoped deny-by-default
  contract (FS-180/FS-540).
- CI: 22 PASS / 4 FAIL (was 21/5).

## Remaining gap (BLOCKED)

`network-renderer-nixos` still has four reds:

1. `test-overlay-core-local-hostile-return-routes.sh` and
   `test-transit-endpoint-return-routes.sh` use the private fixture
   `tests/fixtures/tri-site-s-router-overlay-egress`, which predates FS-322
   (access `selects`), FS-460 (overlay `peerNodes` endpoint identity, overlay as
   egress surface) and now fails four successive compiler diagnostics. A partial
   migration was attempted and reverted rather than left half-applied. The
   authoritative replacement must be a canonical tri-site example in
   `network-labs`; that repository has no tri-site overlay example, and the
   forwarding model's tri-site fixture is intent-only (no host inventory), so the
   renderer cannot derive the fixture from an authoritative source today.
2. `test-policy-cpm-firewall-parity.sh` and the remaining flags of
   `test-runtime-origin-loopback-egress-render.sh` need the per-ingress policy
   table to carry the selected exit default. FS-315 requires the ingress table,
   forward path and return path to share one modeled owner/lane; the canonical
   record currently carries the default on the egress lane only, and no modeled
   ingress-table relation exists to copy. Specifying that relation belongs to the
   GAMP set (which this run was told not to touch), and inventing the mapping in
   CPM would violate FS-171/FS-315.

Recorded upstream: `network-renderer-nixos:docs/blockers.md` (commit `d41bba6`).
