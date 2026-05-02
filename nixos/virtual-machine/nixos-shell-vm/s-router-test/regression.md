# s-router-test regression state

Last updated: 2026-05-02.

## fixed and live-verified

- `network-renderer-nebula` owns Nebula bootstrap/runtime materialization;
  `s-router-test` consumes the rendered module instead of carrying a local
  bootstrap implementation.
- `s-router-test` and `s-router-test-clients` were split so router containers
  stay on the router VM and endpoint fixtures live in the client VM.
- Earlier full `s-router-test` loop reached `ready=true`, passed site-C probing,
  passed hostile IPv4 public egress, and cleaned Hetzner resources.

## fixed but only locally tested

- `network-renderer-nixos` now exposes a host artifact module that installs full
  renderer/debug artifacts under `/etc/network-artifacts` plus a renderer
  summary under `/etc/network-renderer`.
- Renderer regression tests passed:
  `tests/test-host-build-artifact-module.sh` and
  `tests/test-host-build-container-selection.sh`.
- Commit pushed: `network-renderer-nixos` `2419350`
  (`install full renderer artifacts`).

## implemented but not yet live-validated

- `s-router-test` and `s-router-test-clients` import
  `builtHost.artifactModule`; `nixos/flake.lock` was bumped locally to consume
  renderer commit `2419350`.
- Background rebuild loops are running for both VMs. The currently reachable
  `s-router-test` generation is still the pre-artifact generation:
  `/nix/store/yn9myklvw608pmc9w1cg5ia7mbgrlkc2-nixos-system-s-router-test-25.11.20260429.755f5aa`.
- `/etc/network-artifacts` is therefore not yet present on the reachable router
  VM; verify again after the background loops finish.

## still broken

- Hostile DNS is not healthy in the currently reachable generation.
- `b-router-access-hostile` runs Unbound and listens on `10.70.10.1`,
  `fd42:dead:feed:70::1`, localhost IPv4, and localhost IPv6.
- Queries to local Unbound return immediate `SERVFAIL`; tcpdump on
  `b-router-access-hostile` `transit` sees zero packets for those Unbound
  queries.
- Raw `dig @10.20.10.1` and `dig @fd42:dead:beef:10::1` from
  `b-router-access-hostile` do send packets out `transit`, but both time out.
- `b-router-downstream-selector`, `b-router-policy`, and
  `b-router-upstream-selector` have explicit hostile/east-west forwarding rules
  and policy routes; the next failure boundary is the hop after access emits
  raw DNS toward the site DNS provider.

## pending or unknown

- Cross-VM endpoint-to-router DNS from `s-router-test-clients` is pending until
  the current client rebuild returns.
- External hostile delegated IPv6 inbound via Hetzner is pending for the current
  lock graph.
- Artifact installation on both VMs is pending background loop completion.

## next concrete debugging target

- Trace one raw DNS packet from `b-router-access-hostile transit` through
  `b-router-downstream-selector access-hostile`, `b-router-policy
  downstr-hostile/up-hostile-ew`, `b-router-upstream-selector pol-hostile-ew`,
  and `b-router-core-nebula`.
- If the packet reaches `b-router-core-nebula`, debug Nebula/east-west return.
  If it stops earlier, patch the owning CPM/renderer layer, not local VM glue.

## assumptions in the wrong layer

- Any local helper that injects routes, resolver policy, firewall exceptions, or
  overlay runtime behavior remains suspect and must move to CPM or the relevant
  renderer once proven.
- Full artifact/debug bundle installation belongs in `network-renderer-nixos`;
  the VM harness should only import the rendered module.
