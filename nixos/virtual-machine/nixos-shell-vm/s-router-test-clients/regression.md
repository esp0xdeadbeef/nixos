# s-router-test-clients Regression State

Last updated: 2026-05-06 16:40 UTC.

Current pass: failed for production readiness. DNS and route-get-only checks
passed earlier, but live IPv4 internet from `admin-test` is broken and is now a
required post-loop gate.

## Fixed and Live-Verified

- The latest rebuild loop built and rebooted `s-router-test-clients`
  successfully.
- Live `nixos-container list` contains only the expected site-A clients,
  branch/hostile endpoints, and DMZ service fixtures:
  `admin-test`, `branch-node01`, `client-test`, `client2-test`, `dmzweb01`,
  `hostile-node01`, `mgmt-test`, `nebula01`, and `wireguard01`.
- Endpoint DNS and route sweeps passed for all expected client containers, but
  those checks were incomplete because they did not require real IPv4 internet
  egress.
- `branch-node01` now resolves through the branch access DNS path after the
  renderer Unbound recovery fix and updated lock boot.
- `hostile-node01` resolves through its access DNS path and participates in the
  hostile delegated IPv6 public-egress probe.

## Fixed but Only Locally Tested

- No current items.

## Still Broken

- `admin-test` has an IPv4 default route via `10.20.15.1`, but live
  `curl -4 ifconfig.me` hangs and `ping -4 1.1.1.1` fails with 100% packet
  loss.
- `scripts/tests-from-s-router-test-clients.sh` now derives expected
  public-egress gateways from the locked artifacts and fails production
  validation until intent-derived client IPv4 and IPv6 internet work.

## Pending / Unknown

- Re-run this sweep after any model, renderer, lock, or runtime/SOPS change.
- CLAB client parity is outside this file and needs its own current evidence.

## Next Concrete Debugging Target

- Keep endpoint validation tied to the rebuild loop and require actual
  `ping -4 1.1.1.1`, `curl -4 ifconfig.me`,
  `ping -6 2606:4700:4700::1111`, and `curl -6 ifconfig.me` from every client
  container whose default gateway is derived from a public-egress tenant in the
  artifacts.
