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
- `network-renderer-nebula` renders the Hetzner lighthouse NixOS module. The
  bootstrap no longer creates remote systemd units, downloads Nebula with curl,
  or mutates remote iptables/ip6tables.
- `s-router-test` consumes `network-renderer-nebula`'s bootstrap module; the
  stale local `modules/nebula-bootstrap.nix` copy was removed.
- `hetzner-nebula-prodtest-01` was installed with `nixos-anywhere` from
  `nixosConfigurations.s-router-hetzner-anywhere` after the spawn script wrote
  generated runtime IPs, floating prefixes, and SSH keys into `runtime.nix`.
- Latest full loop: `./scripts/s-router-test-rebuild-loop.sh s-router-test`
  passed. `nixos-anywhere` completed, the NixOS Hetzner validator returned with
  IPv6 routing, `s-router-test` rebooted, local build passed, normalized
  renderer JSON matched the running system, Nebula CA/profile issuance
  succeeded, validation became `ready=true`, site-C probe passed, hostile
  public-egress probe passed, and Hetzner resources were cleaned up.
- Latest running `s-router-test` system:
  `/nix/store/bxr2drg5qnhdxngdgvwbdpczhasyvv26-nixos-system-s-router-test-25.11.20260429.755f5aa`.
- Latest local nixos-shell build:
  `/nix/store/v26dg089fi3d68vsl4ibdi6gz96gh549-nixos-vm`.
- `/run/s88-network-validation/status.json` and `stable.json` both reported
  `ready=true`; branch and hostile access DNS checks were `ok` for A and AAAA.
- Hetzner cleanup verified zero remaining servers and zero floating IPv6
  allocations for the latest run name `s-router-test-rebuild-loop-1777668985`.

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

- Cross-VM client-to-router traffic was not validated; the current verification
  proves the router VM split and the standalone client fixture VM.
- `runtime.nix` for `s-router-hetzner-anywhere` is intentionally committed with
  placeholders and fails evaluation until the rebuild loop writes concrete
  Hetzner runtime values.
- Placeholder `s-router-hetzner-anywhere` eval was checked and fails loudly on
  missing `authorizedKeys`, as intended.

## still broken

- No current blocker from the latest `s-router-test` loop. The remaining gap is
  broader than this change: cross-VM client-to-router validation still needs a
  dedicated run with `s-router-test-clients`.

## pending or unknown

- External inbound delegated IPv6 was not re-tested in this run; the loop
  verified hosted NixOS validator install, Nebula profile issuance, host
  validation readiness, site-C probe, and hostile public egress.
- `hostile-node02` is not present in the current running container set.

## next concrete debugging target

- Run a focused external inbound delegated-IPv6 probe against the new NixOS
  Hetzner validator path when `hostile-node02` is present in the client VM.

## assumptions in the wrong layer

- The old local `s-router-test` Nebula bootstrap module and Hetzner
  east-west-exit shell mutation helper were removed. Remaining temporary
  underlay endpoint route prep still needs ownership review.
- The wrapper `scripts/exec-in-s-router-test-machine.sh` points to
  `/home/deadbeef/github/network-codex-agent/scripts/exec-on-remote.sh`, which is absent in this
  checkout; production validation used the repo-local remote wrapper directly.
