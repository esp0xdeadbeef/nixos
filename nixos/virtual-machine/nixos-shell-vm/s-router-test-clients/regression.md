# s-router-test-clients Regression State

Last updated: 2026-05-10 13:52 UTC.

Current pass: red until rerun. The latest completed live loop failed the
site-c DNS-over-overlay probe, so endpoint DNS and internet access cannot be
trusted yet. Since that failure, renderer-nixos `6830834` is pushed and local
NixOS lock commit `c537d20 bump lock` points at it.

## Fixed and Live-Verified

- No current endpoint production-ready state is verified.

## Fixed but Only Locally Tested

- Renderer `6830834` fixes two live-traced materialization defects:
  public-ingress service replies now get `ct status dnat` SNAT, and mixed
  IPv4/IPv6 DNS forwarder sets make Unbound prefer IPv4 when both families are
  configured.
- `bash tests/test-passing-fixtures.sh` passed after the fix, including
  `public-ingress-module`, `public-overlay-service-forwarding`,
  `dns-dual-stack-forwarders-prefer-ipv4`, selector cross-connect guards, and
  full network-labs output rendering.

## Implemented but Not Yet Live-Validated

- NixOS lock commit `c537d20 bump lock` points at renderer-nixos `6830834`.
- Endpoint status remains red until a clean rebuild loop and endpoint probes
  pass from client/admin/client2/hostile contexts.
- `network-codex-agent` `48faf2e` and `2dfc295` fix Hetzner cleanup
  orchestration. The 13:03 UTC run was aborted before endpoint validation and
  all Hetzner resources were deleted; normal cleanup now wakes the tmux
  watchdog with `pkill sleep`.
- `network-codex-agent` `3e8fc88` fixes the pre-spawn access-node lookup delay;
  no endpoint validation result exists yet for that change.
- A later 13:16 UTC loop started the expected concurrent jobs but failed before
  endpoint validation when the concurrent `s-router-clab` backend fixture sweep
  failed on a local CLAB artifact-validator scratch-directory bug. Hetzner
  cleanup was completed from tmux afterward; no Hetzner resources remain.
- `network-renderer-containerlab-linux-backend` `a0069af` is pushed and NixOS
  lock-only commit `e4620b2 bump lock` points at it. The focused
  `overlay-east-west` render/artifact validation passes with `clab-fabric/`
  absent.
- `network-codex-agent` `924707f` is pushed. It preserves runtime failure logs
  and runs observed runtime failures before static/theoretical checks.

## Still Broken

- The last completed live loop failed:
  `dig -b 10.70.10.1 +time=3 +tries=2 @10.90.10.1 example.com A`.
- On stale live builds, endpoint routes existed but public egress and DNS were
  not reliable. That evidence remains red until retested against `6830834`.

## Pending / Unknown

- Endpoint IPv4/IPv6 public egress, DNS-over-overlay, direct public DNS leak
  prevention, and route selection after the fresh locked rebuild.
- Client/admin/client2/hostile contexts were not reached in the 13:16 UTC loop
  because the loop failed during concurrent CLAB validation before live endpoint
  probes.
- The 13:16 UTC CLAB runtime failure is captured as an observed-runtime
  hard-fail in `network-codex-agent`; it points at a preserved full log rather
  than embedding filtered output.
- Whether CPM/model validation must reject DNS forwarder address-family mixes
  that do not have proven upstream reachability.

## Next Concrete Debugging Target

- After any `network-*` chain change, push the owning repo, bump and commit
  downstream locks, then run `s-router-full-lab-rebuild-loop.sh`. The loop must run
  all `network-*` tests, excluding `network-codex-agent`, concurrently next to
  the live endpoint/router/Hetzner validation.
- If the previous CLAB validator failure is not reproduced, remove the
  observed-runtime hard-fail and run live `ip route get`, `ip -6 route get`,
  `ping`, `traceroute`, and `dig` probes from the client/admin/client2/hostile
  endpoint containers.
