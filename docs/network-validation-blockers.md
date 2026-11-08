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
