# `s-router-test` Security Regression Log

Current verified state as of 2026-04-26 04:58 CEST.

## fixed and live-verified

- `b-router-access-hostile` now has an on-link route for the advertised hostile GUA prefix: live `ip -6 route get` for a hostile SLAAC address from the transit side selects `dev tenant-hostile proto static`.
- `hostile-node01` receives a SLAAC address from `2a01:4f8:1c17:b337::/64`; the access router still does not own a GUA infrastructure address from that prefix.
- `b-router-core-nebula` receives Nebula split-default IPv6 routes from rendered unsafe routes: live `ip -6 route get 2606:4700:4700::1111 from 2a01:4f8:1c17:b337::1234 iif upstream` selects `dev nebula1`.
- `b-router-core-nebula` has runtime forwarding rules for `upstream -> nebula1` and `nebula1 -> upstream` in `table inet router chain forward`.
- The current NixOS lock tracks pushed fixes through `network-renderer-nixos=142d9ae` and `network-renderer-nebula=61030a1`.

## fixed but only locally tested

- `network-compiler` preserves tenant `ra6Prefixes` through compiler normalization.
- `network-forwarding-model` routes tenant-advertised IPv6 prefixes without assigning those prefixes to infrastructure addresses.
- `network-control-plane-model` emits hostile access RA prefixes from model data: `2a01:4f8:1c17:b337::/64` is advertised on `tenant-hostile`, while the router interface subnet remains `fd42:dead:feed:70::/64`.
- `network-renderer-nixos` consumes modeled RA prefixes, emits an on-link route for them, and has a focused test proving hostile GUA is advertised without assigning `2a01:4f8:1c17:b337::1/64` to the access router interface.
- `network-renderer-nebula` focused plan tests pass with the updated model chain and assert split-default install flags.
- `network-renderer-containerlab-linux-backend` test suite passes with the updated model chain.

## verified commands

- `nixos`: `nix eval path:/home/deadbeef/github/nixos#nixosConfigurations.s-router-test.config.system.name`
- `nixos`: `nix build --no-link path:/home/deadbeef/github/nixos#nixosConfigurations.s-router-test.config.system.build.toplevel`
- `network-compiler`: `bash tests/check.sh`
- `network-forwarding-model`: `bash tests/test.sh`
- `network-control-plane-model`: `for t in tests/*.sh; do bash "$t"; done`
- `network-renderer-containerlab-linux-backend`: `bash tests/test.sh`
- `network-renderer-nixos`: `bash tests/test-hostile-gua-advertisements.sh`, `./render-all.sh`, `bash tests/test-dual-wan-branch-overlay.sh`
- `network-renderer-nebula`: `bash tests/test-nebula-plan.sh`, `bash tests/test-nebula-plan-from-paths.sh`

## implemented but not yet live-validated

- `s-router-test` now prepares underlay host routes for static Nebula lighthouse endpoints before starting `nebula-runtime`, so installed split defaults do not capture the tunnel endpoint itself. Live iteration found two bugs in that helper: missing `awk` in PATH, then over-broad YAML list parsing that pinned VPN lighthouse addresses to the underlay. It now exports a deterministic Nix PATH, only parses `host:port`/`[v6]:port` endpoint list entries, and deletes stale explicit VPN-host routes.
- `s-router-test` now inserts runtime-only nft forward rules for `b-router-core-nebula` between `upstream` and `nebula1`, because the base rendered firewall cannot reference the runtime tunnel interface yet.
- `scripts/s-router-test-hetzner-east-west-exit.sh` now routes `2a01:4f8:1c17:b337::/64` back through the current modeled `b-router-core-nebula` Nebula address `fd42:dead:beef:ee::2`, not stale `fd42:dead:beef:ee::30`.
- `s-router-test` now emits remote lighthouse `tun.unsafe_routes` only for the hostile delegated prefix via the modeled `b-router-core-nebula` overlay address. Live packet capture showed Hetzner injected echo replies into `nebula0`, but the remote Nebula config only had firewall `local_cidr` entries, not unsafe routes.
- `scripts/s-router-test-rebuild-loop.sh` now probes hostile GUA egress from `hostile-node01` on `eth0` and probes Nebula route selection from `b-router-core-nebula`. The previous helper expected `nebula1` inside `hostile-node01`, which is invalid for the access-client design and produced false-positive "passed" logs.
- `scripts/s-router-test-rebuild-loop.sh` now preflights the disposable Hetzner validator before syncing/building/rebooting `s-router-test`. This avoids a destructive reboot loop when the mandatory external validator is already unreachable and hostile GUA validation cannot complete.
- `~/github/scripts/s-router-test-rebuild-loop.sh` was run at 2026-04-26 04:58 CEST and failed before reboot, as intended, because `46.224.173.254` did not answer public IPv4 ping.

## still broken or unknown until live retest

- External validation host `46.224.173.254` is currently unreachable by public IPv4 ping/SSH, unreachable over the east-west Nebula overlay from `b-router-core-nebula`, and unreachable over the site-c storage Nebula overlay from `c-router-nebula-core`. Direct checks at 2026-04-26 04:58 CEST showed `ping -c1 -W2 46.224.173.254` with 100% packet loss and `ssh -o BatchMode=yes -o ConnectTimeout=5 root@46.224.173.254 true` timing out. No local Hetzner API/CLI token is available for out-of-band recovery. The last failed bootstrap deployed a bad lighthouse config that installed split-default unsafe routes on Hetzner; the local generator is fixed to stop doing that, but the disposable Hetzner host needs out-of-band recovery or reboot before live validation can continue.
- The live `/persist/nebula-runtime/profiles/east-west-hetzner-nebula-prodtest-01.config.yml` on the currently booted `s-router-test` generation is stale and still contains the bad split-default unsafe routes. Do not reuse it as proof of the patched local tree.
- Hostile public IPv6 egress cannot be completed while the Hetzner validator is unreachable. The local path to `b-router-core-nebula` selects `nebula1`, but the lighthouse peer is not responding.
- The prior live validation snapshot reported `ready:true` while individual DNS checks and `b-router-core-nebula` system state were not clean. Treat `ready:true` as insufficient until all per-check statuses pass.
- The hostile egress helper previously printed a pass after visible probe errors. The next loop output must be read critically; do not accept the summary line without route and curl/ping evidence.

## assumptions in the wrong layer

- Local `s-router-test` Nebula/bootstrap code still contains behavior that should come from model/renderers, especially delegated prefix and overlay runtime materialization. Keep removing this from local harness code as the `network-*` schemas grow.
- Local `s-router-test` still injects runtime firewall allowances for `nebula1`; the long-term owner should be a renderer/schema output for runtime overlay forwarding intent, not per-lab glue.
- Local `s-router-test` still pins Nebula static host map endpoints outside split defaults at service start; the long-term owner should be the Nebula renderer or model data for endpoint underlay reachability.
- Local `s-router-test` still computes remote lighthouse unsafe routes for delegated hostile prefixes; the long-term owner should be `network-renderer-nebula` using CPM/model data that identifies overlay exit gateways and delegated external prefixes.
- Validation readiness should fail hard on degraded containers and DNS failures; current status semantics are too weak for production readiness.

## next concrete debugging target

- After Hetzner out-of-band recovery, rerun `~/github/scripts/s-router-test-rebuild-loop.sh`; it should pass the preflight and proceed through locked-input build, reboot, CA unlock, Hetzner prep, and live probes.
- `hostile-node01` receives `2a01:4f8:1c17:b337::/64` by RA/SLAAC.
- `b-router-access-hostile` routes hostile GUA traffic into the modeled downstream path without owning a GUA infrastructure address.
- `b-router-core-nebula` sends `::/1` and `8000::/1` via Nebula, not underlay `eth0`.
- Hetzner routes `2a01:4f8:1c17:b337::/64` back over Nebula with no NAT66.
- Hostile IPv6 curl/ping succeeds end-to-end and DNS does not leak to direct public resolvers unless explicitly modeled.
- After Hetzner recovery, first remove any stale split-default routes on Hetzner (`0.0.0.0/1`, `128.0.0.0/1`, `::/1`, `8000::/1`) from the `nebula0` table state and confirm the regenerated remote config contains only `2a01:4f8:1c17:b337::/64` under `tun.unsafe_routes`.
