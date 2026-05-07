# s-router-hetzner-anywhere Regression State

Last updated: 2026-05-06 16:40 UTC.

Current external pass: passed for the disposable validator used by the latest
`s-router-test` rebuild loop and direct follow-up recheck.

## Fixed and Live-Verified

- The latest locked rebuild loop built the Hetzner toplevel and completed the
  disposable Hetzner deploy.
- The external validation path issued Nebula profiles and passed both the
  site-C DNS-over-overlay probe and hostile delegated IPv6 public-egress probe.
- The disposable Hetzner host was rechecked directly after the previous loop:
  SSH worked, nftables was loaded, and IPv4 plus IPv6 default route checks
  passed.
- The Hetzner/site-C Nebula runtime was active inside `c-router-nebula-core`.
  The container had `nebula1` up, UDP 4242 listening, routes to branch hostile
  prefixes selecting `nebula1`, and nftables default-drop input/forward chains
  with explicit public ingress, underlay, overlay, and Nebula forwarding rules.
- The current loop preserved the same disposable validator with a cleanup
  watchdog after successful external probes.
- Direct follow-up recheck passed: SSH, nftables, IPv4/IPv6 default routes,
  `c-router-nebula-core` Nebula runtime, UDP 4242 listener, branch hostile
  routes selecting `nebula1`, and default-drop nftables policy.

## Pending / Unknown

- The current Hetzner validator is disposable and has a scheduled cleanup
  watchdog. Revalidate with a fresh runtime/SOPS injection on the next rebuild
  loop rather than treating this machine as permanent state.
- `scripts/tests-from-s-router-test-clients.sh` is now wired into the
  `s-router-test` rebuild loop and checks the Hetzner nft baseline when
  `HETZNER_VALIDATOR_HOST` is present. This still needs a fresh loop run after
  the current client/policy route failures are fixed.
- CLAB parity is outside this file.

## Boundary Notes

- This host is disposable external validation state, not the source of truth.
  Public addresses, delegated prefixes, and provider facts must stay in the
  runtime/SOPS flow and must not be copied into plain model or NixOS files.
