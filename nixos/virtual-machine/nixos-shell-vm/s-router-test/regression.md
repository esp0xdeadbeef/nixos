# s-router-test Regression State

Last updated: 2026-05-07 19:43 UTC.

This file records current verified state only. Treat older claims as stale until
revalidated through `scripts/s-router-test-rebuild-loop.sh` and live checks.

Current pass: failed live rebuild. The locked chain built, deployed, rebooted,
issued Nebula credentials, and fixed the prior site-C DNS-over-overlay failure.
Production readiness now stops at hostile delegated IPv6 public egress from
`s-router-test-clients`.

## Fixed and Live-Verified

- Repository guards passed before rebuild: no plain public IP literals in NixOS
  config, no local `s-router-test` nftables/iptables policy glue, and the
  network repository clean guard was green.
- Lock propagation reached NixOS local commit `8b1a439` with:
  - CPM `7d63aba`
  - containerlab renderer `fbad7d2`
  - Nebula renderer `2846f3a`
  - NixOS renderer `cf377b7`
- `s-router-test`, `s-router-test-clients`, and Hetzner toplevel builds passed.
  Both local SSH targets returned after reboot, and the post-reboot renderer
  JSON matched the local build.
- Hetzner deploy completed, Nebula CA unlock/profile issuance completed, and
  `s88-network-validation` started with a snapshot.
- Site-C DNS-over-overlay now passes from `b-router-access-hostile` for both
  families:
  - `dig -b 10.70.10.1 @10.90.10.1 example.com A`
  - `dig -b fd42:dead:feed:70::1 @fd42:dead:cafe:10::1 example.com AAAA`
- The branch hostile path to site-C DNS selects Nebula as intended:
  `b-router-core-nebula` routes `10.90.10.1` and
  `fd42:dead:cafe:10::1` through `nebula1`.
- CPM service-ingress route augmentation fixed the previous site-C lighthouse
  loop. Public Nebula packets now reach the site-C lighthouse path far enough
  for DNS-over-overlay to work.

## Fixed but Only Locally Tested

- CPM service-ingress route augmentation is covered by
  `tests/test-public-overlay-service-binding.sh`; focused CPM DNS/service route
  tests and full `tests/test-passing-fixtures.sh` passed before downstream lock
  propagation.
- `network-renderer-nixos` consumed CPM `7d63aba`; focused DNS/service tests
  and full `tests/test-passing-fixtures.sh` passed.
- `network-renderer-containerlab-linux-backend`
  `tests/test-dns-service-policy-routes.sh` passed after its lock bump.

## Still Broken

- Latest verified live failure: hostile delegated IPv6 public egress from
  `hostile-node01` on `s-router-test-clients`.
- Endpoint facts:
  - `hostile-node01` has IPv4 internet working.
  - It receives delegated IPv6 addresses in `2a01:4f9:c01f:ab::/64`.
  - `ip -6 route get 2606:4700:4700::1111` selects `dev eth0` via RA from
    `b-router-access-hostile`.
  - `ping -6 2606:4700:4700::1111` loses all packets.
- Branch-side routing is coherent:
  - `b-router-access-hostile` forwards delegated-source traffic to `transit`.
  - `b-router-policy`, from `downstr-hostile`, selects `up-hostile-ew`.
  - `b-router-upstream-selector`, from `pol-hostile-ew`, selects
    `core-nebula`.
- Site-C delegated-prefix route activation is wrong:
  - The rendered dynamic route services exist in `c-router-core`,
    `c-router-upstream-selector`, and `c-router-nebula-core`.
  - The Hetzner runtime secret tree did not copy
    `access-node-ipv6-prefix-*` files to the validator, so those services
    no-op and only placeholder ULA routes remain active.
  - This is a `network-codex-agent` runtime injection bug. The model/rendered
    route services cannot install the real delegated public prefix when their
    runtime secret input is missing.

## Implemented but Not Yet Live-Validated

- A failing `network-codex-agent` regression now checks that the Hetzner
  runtime extra-files secret tree contains per-access
  `access-node-ipv6-prefix-*` files derived from routed IPv6 assignments.

## Pending / Unknown

- Finish and validate the runtime secret-tree fix, then rerun
  `scripts/s-router-test-rebuild-loop.sh` and recheck:
  - hostile delegated IPv6 public egress
  - IPv4 public egress
  - DNS leak prevention
  - Nebula reachability
  - nftables lane policy
  - `s-router-clab` gate

## Next Concrete Debugging Target

- Fix Hetzner runtime secret-tree generation so it writes the routed IPv6
  assignment JSON into per-access `access-node-ipv6-prefix-*` secret files.
  The expected post-rebuild proof is that site-C containers have those files
  under `/run/secrets`, install routes for the actual delegated public `/64`
  prefixes, and `hostile-node01` can reach IPv6 internet through the modeled
  Nebula return path.

## Assumptions in the Wrong Layer

- Scripts may wait, deploy, clean up, and validate. They must not invent routes,
  DNS policy, nftables policy, bridge/macvlan allocation, or overlay runtime
  behavior.
- Renderers may only emit explicit CPM/provider output. Any future fix that
  reparses `intent.nix`, `inventory*.nix`, names, roles, or provider strings in
  a renderer is a wrong-layer regression.
