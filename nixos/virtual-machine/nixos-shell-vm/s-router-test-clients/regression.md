# s-router-test-clients Regression State

Last updated: 2026-05-12 00:55 UTC.

This file is current-state evidence only. Older entries are stale until
reverified.

## Fixed and Live-Verified

- No current endpoint production-readiness result is verified after the latest
  aborted full-lab run.

## Fixed but Only Locally Tested

- No client endpoint fix is considered live-verified from the current check.

## Implemented but Not Yet Live-Validated

- The NixOS tree contains dirty client-side changes renaming the local site
  identity from `site-a` to `nixos`. They are not treated as live evidence until
  the full locked rebuild loop completes.
- The full-loop run rebooted `s-router-test-clients`; SSH returned and the
  client build passed before the run failed on Hetzner remote build SIGKILL and
  red CLAB state. Endpoint route, DNS, firewall, and leak checks are still
  pending because the router/validator side did not complete production checks.

## Still Broken

- Client-side production readiness is unknown because the router topology is
  not yet green.
- Endpoint DNS, IPv4/IPv6 egress, direct public DNS leak prevention, and
  overlay route selection have not been verified from the actual client
  containers on a current returned generation.

## Pending / Unknown

- `ip route get`, `ip -6 route get`, resolver configuration, bounded `dig`, and
  nftables evidence from each endpoint context after the next full rebuild.

## Next Concrete Debugging Target

- Let the full rebuild loop reboot `s-router-test-clients`, then capture live
  endpoint route and DNS evidence only after the router side is reachable and
  host validation has returned.

## Assumptions in the Wrong Layer

- Endpoint route, DNS, and firewall behavior must come from the locked
  model/render chain. Local client harness glue must not invent policy.
