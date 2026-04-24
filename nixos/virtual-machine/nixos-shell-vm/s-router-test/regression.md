# `s-router-test` Regression Status

Verified on 2026-04-24 from the locked `~/github/nixos` chain after the latest live reboot.

Treat everything below as current verified state only.

## fixed and live-verified

- Host validation no longer crash-loops on jq variable expansion. `s88-network-validation.service` is active and produces a live snapshot.
- Direct public DNS leak prevention on the access routers is fixed live. Verified from `mgmt-test`: direct `dig @1.1.1.1 example.com A` times out while `ping 1.1.1.1` still succeeds.
- `network-renderer-nixos` `1cbd3bb` is fixed live. Verified on `s-router-access-mgmt`: `unbound` now renders `outgoing-interface: 10.20.10.1` and `outgoing-interface: fd42:dead:beef:10::1`, and local `dig @127.0.0.1 example.com A/AAAA` succeeds.
- DNS over the modeled mgmt resolver path is fixed live for the site A routers. Verified on `s-router-access-admin`: `dig @10.20.10.1 example.com A` succeeds, and local `dig @127.0.0.1 example.com A` also succeeds.
- Site A and DMZ tenant endpoints now use the modeled in-lane resolver path live instead of public resolvers. Verified on `admin-test`, `mgmt-test`, `client-test`, `client2-test`, and `dmzweb01`:
  - `networkctl status eth0` and `resolvectl status` show router DNS on `eth0`,
  - plain `dig example.com A` succeeds through `127.0.0.53`,
  - and direct `dig @1.1.1.1 example.com A` still times out.
- Site A mgmt resolver ACL derivation for branch consumers is fixed live. Verified on `s-router-access-mgmt`: `unbound` now includes branch transit/source ranges such as `10.50.0.0/31`, `10.60.10.1/24`, `fd42:dead:feed:1000::/127`, and `fd42:dead:feed:10::1/64` in `access-control`.
- The modeled policy allowance for east-west traffic to the site A mgmt DNS service is fixed live. Verified on `s-router-policy-only`: `allow-east-west-to-sitea-mgmt-dns` now renders live for UDP/TCP 53 from the east-west uplink interfaces to `downstream-mgmt`.
- Branch WAN DNS scoping is fixed live. Verified on `b-router-policy`: `deny-branch-dns-to-wan` renders only on `upstream-branch`, not on `up-branch-ew`, while `allow-branch-to-east-west` still renders on `up-branch-ew`.
- Branch recursive DNS is fixed live. Verified on `b-router-access-branch`: local `dig @127.0.0.1 example.com A` succeeds, while direct `dig @1.1.1.1 example.com A` still times out.
- Branch tenant DNS is fixed live through the modeled local resolver path. Verified on `branch-node01`: `resolvectl query example.com` and `getent hosts example.com` both succeed, and `resolvectl dns eth0` shows only `10.60.10.1` and `fd42:dead:feed:10::1`.
- The modeled core overlay path is fixed live for the current `100.96.10.0/24` overlay. Verified on `s-router-core-isp-b`: `overlay-west` is up with `100.96.10.1/32`, `ip route get 100.96.10.2` selects `dev overlay-west`, and `ping 100.96.10.2` succeeds.
- Current host validation snapshot reports `dnsA=ok` and `dnsAAAA=ok` for `b-router-access-branch`, `s-router-access-admin`, `s-router-access-client`, `s-router-access-client2`, `s-router-access-dmz`, and `s-router-access-mgmt`.

## fixed but only locally tested

- The renderer overlay/example regression tests are no longer allowed to bypass the locked `network-labs` input via sibling worktrees. Locally verified:
  - `network-renderer-nixos/tests/test-dual-wan-branch-overlay.sh` now resolves examples from the locked flake input and passes.
  - `network-renderer-nixos/tests/test-missing-wan-group-assignment.sh` now resolves examples from the locked flake input and passes.
  - `network-renderer-containerlab-linux-backend/tests/test-dual-wan-branch-overlay.sh` no longer falls back to `../network-labs/examples` and passes.
- The NixOS WAN service / DNAT regression test is now locked-example based instead of using the in-repo `s-router-test` fixture. Locally verified:
  - `network-renderer-nixos/tests/test-port-forward-rendering.sh` now uses `network-labs/examples/single-wan` and passes.

## implemented but not yet live-validated

- None currently recorded.

## still broken

- The topology is not production-safe.
- Direct branch-router-to-site-A resolver probing is still broken live even though branch tenant DNS works. Verified on `b-router-access-branch`:
  - local `dig @127.0.0.1 example.com A` succeeds,
  - but direct `dig @10.20.10.1 example.com A` still times out,
  - and `ip route get 10.20.10.1` still uses `via 10.50.0.1 dev transit src 10.50.0.0`.
- The transitional Nebula runtime bridge is still broken live and still does not match the modeled overlay. Verified on `branch-node01` and `nebula-core`:
  - both still run `nebula1` on `100.64.10.10/24` and `100.64.10.1/24`,
  - `branch-node01` still attempts handshakes to stale `vpnAddrs="[100.64.10.1]"` and stale underlay `udpAddrs="[10.13.0.89:4242]"`,
  - `branch-node01` still cannot ping `100.64.10.1`,
  - and `s-router-core-isp-b` still routes `100.64.10.10` via underlay `10.13.0.1 dev eth0`.
- The live failure is no longer the rendered profile content itself. Verified on `s-router-test`:
  - `/persist/nebula-runtime/profiles/nebula-core/config.yml` and `/persist/nebula-runtime/profiles/branch-node01/config.yml` now contain modeled `100.96.10.10` and underlay `10.13.0.90:4242`,
  - but `/persist/nebula-runtime/pki/nebula-core.crt` and `/persist/nebula-runtime/pki/branch-node01.crt` still carry `100.64.10.1/24` and `100.64.10.10/24`,
  - and `nebula-runtime` inside the containers started before the rewritten profiles took effect and was not restarted afterward.
- The lab still depends on a dirty local `~/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/default.nix` import of `host-validation.nix`. That wiring is still not proven through a committed locked-chain-only path.

## pending or unknown

- Whether the still-failing direct `b-router-access-branch -> 10.20.10.1` probe matters for production safety beyond debugging convenience, since branch tenant DNS is already working live through the local branch resolver path.
- Whether branch endpoint direct public DNS leak prevention is fully enforced from `branch-node01`. The container currently does not have `dig` installed, so direct `@1.1.1.1` / `@9.9.9.9` query attempts have not yet been live-verified from that endpoint context.
- Whether DNS over the transitional Nebula runtime can or should be validated before the hardcoded `100.64.10.0/24` bootstrap bridge is replaced by modeled overlay data.
- Whether `s-router-test` can successfully authenticate from its own persistent root SSH key to `hetzner-nebula-prodtest-01`; the VPS is reachable, but the `s-router-test` key is not yet authorized there.
- Whether all renderer top-level suites are fully example-backed. Verified remaining local fixture usage still exists in `network-renderer-nixos`:
  - `tests/cases/passing-fixtures.sh`,
  - `tests/lib/test-common.sh` fixture helpers,
  - and the repo-level `test-passing-fixtures.sh` still intentionally invokes that fixture suite even though its VM API smoke now uses the locked `single-wan` example.

## next concrete debugging target

- Reissue Nebula certs and restart `nebula-runtime` after profile generation so `nebula-core` and `branch-node01` actually consume the modeled `100.96.10.0/24` / `fd42:dead:beef:ee::/64` overlay at runtime instead of keeping the stale `100.64.10.0/24` identity.
- Decide whether the remaining renderer fixture suites should be deleted, migrated to `network-labs/examples`, or explicitly kept as non-example unit coverage, then enforce that distinction in the test entrypoints so locked-example validation is never confused with fixture-only smoke tests.
- After that fix, rerun the rebuild loop and live-verify:
  - `branch-node01` <-> `nebula-core` Nebula handshake and reachability,
  - DNS over Nebula from the correct live contexts,
  - and whether the remaining direct `b-router-access-branch -> 10.20.10.1` timeout still exists or disappears with the stale runtime removed.
