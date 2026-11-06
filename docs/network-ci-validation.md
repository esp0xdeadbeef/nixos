# network-* CI validation status

This note records the current, verified state of the `~/github/network-*`
check suites and the one upstream contract that blocks the remaining reds.
It is the blocker record for the "everything validated" goal.

## Verified green (GitHub Actions, this run)

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
| network-renderer-containerlab-linux-backend | `f90dc63` | success (all cases, incl. FS-540-020/035) |

The containerlab renderer now consumes only a validated canonical realization
bundle (FS-310-HDS-040-SDS-010-SMS-100); a raw `control_plane_model` payload is
rejected with `GAMP-MODEL-BOUNDARY-VIOLATION`.

## Fixed this run (network-control-plane-model)

- `64ec24f`: named-core DNS listener/forwarder is the relation's emitted
  terminal attachment endpoint, never the resolver loopback
  (FS-540-HDS-010-SDS-010-SMS-020 "An ownership loopback is not a substitute";
  SMS-035 "a node loopback ... shall not be substituted"). FS-540-010/020/025/
  030/035/040/045 are green in CI.
- `7a4a1c6`: FS-525 named-core and egress-selection cases assert the emitted
  endpoint identity and the declared `egressSurface` determinism.

## Remaining reds and their owner

`network-control-plane-model` is at 19 reds. Every one was reproduced against
the pre-change revision (`git worktree` at `64ec24f^`), so none is a regression
of the FS-540 fix. They split into two groups:

1. **Requester-lane resolver service route (blocked).**
   `test-dns-service-policy-routes`, `test-sitec-overlay-service-ingress`,
   `test-s-router-hetz-overlay-dns-ingress`,
   `test-example-overlay-upstream-policy-defaults-preserved`,
   `test-preferred-uplink-defaults`, `FS-460-HDS-010-SDS-010-SMS-050`.
   The resolver's own lane carries the emitted endpoint host route
   (`service-endpoint-reachability`, relation identity, policy-table
   provenance). There is no requester-lane leg. FS-540 SMS-020 requires
   "relation-owned requester-lane route authority containing policy table,
   outgoing lane, selected next-hop identity, and provenance for each requested
   family and resolver endpoint prefix". That leg is a forwarding-model
   relation-path output; deriving it in CPM would place forwarding meaning in
   the wrong layer and violate FS-171 (consumers import, never re-derive).
2. **Pre-existing module/example migrations (not blocked, unfinished).**
   `FS-260-015`, `FS-310-120`, `FS-380-050`, `FS-410-030`, `FS-420-030`,
   `FS-500-040`, `FS-720-030`, `FS-740-010`, `FS-770-010`, `FS-800-010/012/030`,
   `FS-970-040`.

`network-renderer-nixos` still has 5 reds: `test-client2-policy-uplink-firewall`,
`test-overlay-core-local-hostile-return-routes`,
`test-transit-endpoint-return-routes` (tri-site fixture needs one complete
FS-322 migration), `test-policy-cpm-firewall-parity`, and
`test-runtime-origin-loopback-egress-render` (fixture has no modelled egress
surface).

## Blocked reason

AGENTS requires the owning requirement to be fixed in URS/FS first, in the same
change, before implementation. The requirement text for the missing
requester-lane leg is in `network-codex-agent/GAMP`, which the operator
explicitly excluded from this run ("codex-agent can be skipped"), and that repo
also owns the forwarding-model requirement for the leg. Without either
permission to edit that GAMP set plus the forwarding-model emission, or a
confirmation that the leg is already emitted upstream and merely unconsumed,
the remaining reds cannot be closed without violating the fork's own layer
discipline.

The blocker is recorded upstream as well:
`network-control-plane-model:docs/blockers/remaining-ci-reds.md` (commit
`f0f0ef2`).
