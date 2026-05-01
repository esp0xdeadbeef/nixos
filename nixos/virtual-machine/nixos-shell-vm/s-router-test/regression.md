# s-router-test regression state

## fixed and live-verified

- `network-renderer-nixos` tests now use current rendered node ids for overlay
  route retention, and host-veth consumer sufficiency uses CIDR containment
  instead of string-only route matching.
- Live rebuild loop reached SSH return on
  `/nix/store/kgkkvzf89yszi4d8h5s2pqr5ik7d594a-nixos-system-s-router-test-25.11.20260429.755f5aa`.
- Local build passed with expected system hash
  `6kb4p7qrzy5idzgr3jqgiq71i02mgq3s`; normalized renderer JSON matched the
  running generation.
- `s-router-test` now materializes router/overlay containers only; endpoint
  fixtures are absent from its expected validation container set.
- `s-router-test-clients` rebuilt and rebooted to
  `/nix/store/mzms5r5vw602brm2wkkvyp0zkljfg578-nixos-system-s-router-test-clients-25.11.20260429.755f5aa`.
- All `s-router-test-clients` endpoint containers were running after reboot,
  including `hostile-node01`, `streaming-cast-01`, `nas-node01`, and
  `printer-node01`.
- Client fixture services checked live: `streaming-cast-01`
  `fake-googlecast.socket` active and `dmzweb01` `dmz-web` active.
- Router-side site-C streaming and hostile public-egress probes skip endpoint
  checks now that those endpoint containers live in `s-router-test-clients`.
- Hetzner validator resources were cleaned up after testing:
  server `128785279` and its floating IPv6 allocation were removed.

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

## implemented but not yet live-validated

- The NixOS fabric input fix was used for the live run, but NixOS is local-only
  and was not pushed.
- Cross-VM client-to-router traffic was not validated; the current verification
  proves the router VM split and the standalone client fixture VM.
- `network-renderer-nebula` now renders a declarative Hetzner lighthouse NixOS
  module. The bootstrap no longer creates remote systemd units, downloads
  Nebula with curl, or mutates remote iptables/ip6tables.
- `nixos` now has `s-router-hetzner-anywhere`, a `nixos-anywhere` host for
  `hetzner-nebula-prodtest-01`. Its `runtime.nix` is generated from the Hetzner
  spawn output before deployment and fails evaluation while placeholders remain.
- `network-codex-agent/scripts/s-router-test-rebuild-loop.sh` now writes that
  runtime config and installs the Hetzner validator with `nixos-anywhere` before
  rebuilding `s-router-test`.

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
  `/home/deadbeef/github/network-codex-agent/scripts/exec-on-remote.sh`, which is absent in this
  checkout; production validation used the repo-local remote wrapper directly.
