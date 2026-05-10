# s-router-test Regression State

Last updated: 2026-05-10 17:56 UTC.

Current state: not production-ready. Live online checks found a DNS policy
materialization bug in `network-renderer-nixos`, and the concurrent CLAB
validation is still red.
The latest locked full-lab run also proved the Hetzner validator path is red:
fresh `nixos-anywhere` install completed and rebooted, but SSH to the external
validator returned `Connection refused`.
Console evidence showed `sshd.service` failed because `/etc/ssh/sshd_config`
did not exist.

## Fixed and Live-Verified

- No end-to-end production-ready state is verified. DNS, routes, nftables,
  overlays, CLAB, Hetzner, lane preservation, and leak prevention have not all
  passed in one locked full-lab loop.
- Live selector nftables did not show the original upstream-selector core-core
  crossconnect bug. The upstream selector still looked like a lane mover, not a
  policy router.
- Live downstream selector nftables did not show direct access-access
  forwarding. Access-to-access traffic still requires policy in between.

## Fixed but Only Locally Tested

- `network-codex-agent` now records observed runtime failures as hard-failing
  tests before the theoretical sweeps. The 2026-05-10 online failure is
  preserved under `tests/observed-runtime-failures/logs/` and fails first.
- `network-codex-agent` locally updates the CLAB full-lab postcheck to validate
  current bridge-kind host uplinks instead of stale macvlan markers. Focused
  check passed: `bash tests/test-s-router-clab-current-example-postcheck.sh`.
- `network-renderer-nixos` has a local fix for the access DNS helper that was
  inserting `deny-direct-dns-egress` on `tenant-mgmt` before policy routing.
  Focused renderer checks passed:
  `bash tests/test-dns-service-access-policy-exceptions.sh`,
  `bash tests/test-dual-wan-branch-overlay.sh`, and
  `bash tests/test-dns-service-policy-routes.sh`.
- `network-codex-agent` now raises Hetzner deploy failures before waiting on
  slower CLAB VM finalization, and interrupt cleanup now terminates CLAB/QEMU
  job trees. Focused guards passed:
  `tests/test-s-router-test-cleanup-kills-job-trees.sh` and
  `tests/test-s-router-test-hetzner-fails-before-clab-finalize.sh`.
- `network-codex-agent` now tests the actual cleanup-watchdog `pkill sleep`
  behavior with a fake Hetzner API. The observed bug was that `pkill sleep`
  could interrupt the second `sleep 5` under `set -e`, leaving detached floating
  IPs after server deletion. Focused guard passed:
  `tests/test-s-router-test-hetzner-cleanup-watchdog-pkill-sleep.sh`.
- Live cleanup verification passed after the retry/unassign patch: the
  corrected watchdog removed leaked floating IPs `130193580` and `130193581`,
  and Hetzner then showed no servers and no floating IPs.
- Hetzner SSH impermanence now matches the working l-esp/l-werk/s-sigma
  pattern: `/etc/ssh` is not persisted as a directory, and persistent host keys
  are configured with `services.openssh.hostKeys`. This prevents the persistent
  directory from hiding NixOS-generated `/etc/ssh/sshd_config`.
- A generated UUIDv4 Hetzner root console password is now wired for the next
  fresh install while SSH password login remains disabled. Focused guard passed:
  `tests/test-s-router-test-hetzner-console-password.sh`.

## Implemented but Not Yet Live-Validated

- Hetzner validator reuse is implemented in `network-codex-agent` and pushed as
  `08dbc07 reuse hetzner validators with switch`. Reused NixOS validators take
  the `nixos-rebuild switch` path, and the cleanup watchdog is refreshed for
  another 3600 seconds.
- The current DNS renderer fix is not pushed or lock-propagated yet. The
  locked `s-router-test` build has not consumed it.

## Still Broken

- Live `s-router-access-mgmt` inserted direct DNS drops:
  `iifname "tenant-mgmt" udp/tcp dport 53 drop comment "deny-direct-dns-egress"`.
  This conflicts with intent, where `allow-mgmt-dns-to-uplinks` at priority 16
  explicitly allows mgmt DNS to `isp-a` and `isp-b` before the priority 20
  `deny-sitea-dns-to-uplinks`.
- Latest CLAB loop failed before packet validation on the previous locked
  chain:
  `missing rendered physical VLAN 4` and
  `FAILED: full tri-network CLAB host-uplink VLAN compile test failed`.
- Live `s-router-clab` is not a trustworthy green runtime right now:
  `clab`, `docker`, and `podman` were absent from `PATH`; `clab-trunk` and
  `vlan2` were up, while `vlan4` and `vlan5` were down/no-carrier.
- Live `s-router-core-nebula` still needs review. It had public routes but
  public ping failed, and its ruleset contained broad overlay/core forwarding
  accepts that need to be reconciled with intent before they are trusted.
- `dmzweb01` resolved DNS through the modeled resolver but public IPv4/IPv6
  ping failed. Verify the DMZ intent before deciding whether this is a renderer
  bug or an expected deny.
- Hetzner validator fresh install is red: the install completed, bootloader
  installation succeeded, and the server stayed running in Hetzner, but SSH on
  `204.168.245.145:22` refused connections after reboot. The identified cause
  was missing `/etc/ssh/sshd_config`; the fix is not live-validated yet.

## Pending / Unknown

- Push and lock-propagate the `network-renderer-nixos` DNS fix, then rerun the
  full-lab rebuild loop through the locked chain.
- Fix the CLAB VLAN 4 rendered physical uplink failure in the owning renderer.
- Recheck live client/admin/mgmt/dmz IPv4 and IPv6 egress, direct public DNS
  leak prevention, DNS-over-overlay, and route selection after the locked loop.
- Re-run the full network repo sweep; the latest captured sweep was not clean
  enough to trust as a final result.
- Hetzner console debugging is pending on the next fresh install with generated
  `pw.txt`; the currently failed install did not have a configured root
  password.

## Next Concrete Debugging Target

- Stop the current failed Hetzner run through the cleanup watchdog, rerun
  `~/github/network-codex-agent/scripts/s-router-full-lab-rebuild-loop.sh`,
  and use the generated `pw.txt` root password in Hetzner console if SSH still
  refuses. Capture the exact boot/systemd/network failure before changing model
  or renderer code.

## Assumptions in the Wrong Layer

- An access DNS service must not infer that every tenant interface needs a local
  direct-DNS drop. DNS allow/deny policy is CPM policy output, and the renderer
  may only materialize explicit policy without overriding higher-priority
  allows.
- CLAB physical VLAN presence is renderer/containerlab materialization, not a
  local `s-router-test` shell workaround.
