# s-router-test regression state

## fixed and live-verified

- `network-renderer-nixos` tests now use current rendered node ids for overlay
  route retention, and host-veth consumer sufficiency uses CIDR containment
  instead of string-only route matching.
- Live rebuild loop reached SSH return on
  `/nix/store/887yvy67110s9jhpzd8f7nirjdr5a0h5-nixos-system-s-router-test-25.11.20260429.755f5aa`.
- Local build passed with expected system hash
  `6hrknjnkr21fhz5ysa62wqa2hlykdw3r`; normalized renderer JSON matched the
  running generation.
- Site-C streaming probe passed for IPv4 and IPv6 TCP 8009.
- Hostile public IPv6 egress probe passed through Hetzner.
- Hetzner validator resources were cleaned up after testing:
  server `128780349`, floating IPv6 `128943800`.

## fixed but only locally tested

- `network-labs` examples now bind explicit WAN groups where strict rendering
  requires consumer-side `wanGroupToUplink`.
- `network-forwarding-model` hostile DNS test no longer expects deployment GUA
  prefixes in the forwarding layer.
- `network-control-plane-model` stale fixture tests were updated for current
  `inventory-nixos.nix` example shape and current transit endpoint route
  behavior.
- `s-router-test/default.nix` now uses
  `network-labs/examples/s-router-test-three-site/{intent.nix,inventory-nixos.nix}`
  so Hetzner delegated-prefix secret names are derived from CPM output.
- Endpoint and DMZ fixture containers were moved out of `s-router-test` into
  `s-router-test-clients`; the client VM builds locally as
  `/nix/store/syf6bh6bqngl5rjcrddrfx8kfnmxkgam-nixos-vm`.

## implemented but not yet live-validated

- The NixOS fabric input fix was used for the live run, but NixOS is local-only
  and was not pushed.
- The client split has not been live-validated with both VMs running together.

## still broken

- Production readiness is blocked: `/run/s88-network-validation/status.json`
  and `stable.json` both report `ready=false`.
- `b-router-access-branch` and `b-router-access-hostile` have active DNS
  services but fail A and AAAA lookups.
- Direct checks show both branch access routers forward to `10.20.10.1` and
  `fd42:dead:beef:10::1`, but pings to those forwarders time out.
- Site-A mgmt DNS itself answers locally, so the failure is branch-to-site-A
  DNS reachability, not Unbound on `s-router-access-mgmt`.

## pending or unknown

- Full production DNS, overlay, routing, firewall, lane-preservation, and
  leak-prevention gate remains incomplete because branch DNS is broken.
- External inbound delegated IPv6 was not re-tested after this run because the
  production gate already failed on stable DNS validation.
- `hostile-node02` is not present in the current running container set.

## next concrete debugging target

- Fix local service-origin routing for branch DNS forwarders in the owning
  `network-*` layer. The rendered routes to the site-A DNS prefixes exist in
  ingress policy tables, but locally-originated Unbound traffic has no `iif` and
  falls through to a main table with no route.

## assumptions in the wrong layer

- Local `s-router-test` helpers still materialize runtime overlay/bootstrap and
  route behavior that should remain owned by CPM and renderers.
- The wrapper `scripts/exec-in-s-router-test-machine.sh` points to
  `/home/deadbeef/github/scripts/exec-on-remote.sh`, which is absent in this
  checkout; production validation used the repo-local remote wrapper directly.
