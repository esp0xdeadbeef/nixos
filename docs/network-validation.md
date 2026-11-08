# network-* validation: final state

Every `network-*` repository consumed by this flake is validated end to end.
There are no outstanding red cases and no blocker notes.

## CI (latest run per repository)

compiler, control-plane-model, forwarding-model, labs, realization-model,
realization-schema, renderer-nixos, renderer-containerlab-linux-backend,
renderer-nebula, renderer-wireguard, renderer-access-endpoint-nixos and
site-esp: success.

## Suites (local, same entrypoints as CI)

- control-plane-model: 242 PASS / 0 FAIL
- forwarding-model: 82/82
- labs: 42 PASS / 0 FAIL / 1 skipped
- renderer-nixos: 26/26
- renderer-containerlab-linux-backend: 57 tests
- renderer-nebula: 15/15
- renderer-wireguard: 3/3 (includes `nix flake check`)
- renderer-access-endpoint-nixos: 16/16
- realization-model / realization-schema: `nix flake check -L` all checks passed
- site-esp: new CI validates the SAT generator, its explicit-intent guard and
  tree hygiene

## Cross-layer contracts the tests now assert

- FS-315: every policy route names an explicit context table; no generic
  default on a lane whose modeled uplink offers none; no unassigned route
  copied into a sibling policy lane.
- FS-370: every source prefix that may leave a site binds to the exit that may
  carry it, realized as exactly one preferred-source default per family on the
  modeled route, with the source routed by source into the lane that carries
  it (FS-370-HDS-010-SDS-010-SMS-120).
- FS-460: overlay reachability routes carry the peer overlay next hop; the
  delegated public-egress default is policy-only and lane-bound only when the
  model selects the overlay-owning scope; the delegated hostile prefix returns
  over the modeled policy lane and is installed at runtime from the modeled
  source file (FS-460-HDS-010-SDS-010-SMS-030/-050).
- FS-380: the upstream lane set is the modeled access selection, not the
  physical uplink inventory.

## Hygiene

- No machine-local paths (`/home/<user>`, `~/…`, `/Users/…`) in any tracked
  tree; the site-spec generator requires an explicit intent or
  `NETWORK_SITE_INTENT`.
- No private key material; `network-labs` SOPS payloads stay encrypted and no
  test decrypts them.
- Operator infrastructure literals replaced with documentation ranges
  (TEST-NET IPv4, `2001:db8::/32`); the remaining public literals are
  well-known resolvers/example addresses used as DNS fixtures.

## realization-model / realization-schema: audit and fixes

The two repos were load-bearing but two of their schema guarantees were only
exercised by fixtures:

- `NR_SCHEMA_SHAPE_INVALID` rejected unknown *platform-binding* fields but no
  unknown *bundle* fields. FS-161-HDS-010-SDS-010-SMS-010 requires the schema to
  reject unknown extensions; a bundle could carry an extra top-level field
  (including a second platform-binding sidecar) and still validate. The schema
  now allows exactly the declared envelope (required + optional + the release
  `validation` record) and fails at `/` otherwise
  (`network-realization-schema` 675205d).
- `protectedReferences` was validated by the schema but no producer populated
  it, so every real bundle shipped `[]` and the protected-material checks were
  fixture-only. `network-realization-model` (864693c) now projects every
  `/run/secrets/` leaf the canonical content names into opaque
  `{ reference, classification = "protected" }` records, unions explicitly
  declared references, and rejects a platform binding that references a
  protected path the bundle does not declare
  (`NR_PLATFORM_BINDING_REFERENCE_MISSING`). Completeness is by construction:
  a producer cannot release a bundle that omits a protected reference its own
  content carries.

Verified: both repos' `nix flake check -L` passes; a real CPM output realizes
to a bundle with 5 derived protected references, all `/run/secrets/`, opaque,
and `validateRendererInput` accepts it; `network-labs` pinned to the new
model/schema (63c1740) runs 42 PASS / 0 FAIL, which exercises the full
bundle -> platform binding -> renderer flow.

Observed layering (no change required): the schema validates the bundle and
binding shapes; renderer-consumption and rendered-output coverage manifests are
validated in `network-labs` (FS-168 trace) where they are produced. Platform
bindings are built with all five categories by the labs harness, while the NixOS
host profile realizes the `deployment` category (VM NICs). The other categories
are carried and schema-validated, not yet consumed by a renderer.
