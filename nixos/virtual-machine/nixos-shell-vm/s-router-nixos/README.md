# `s-router-test`

`s-router-test` is a single-VM integration harness for the locked `network-*`
pipeline. It should consume model and renderer output; it should not become the
place where topology, route policy, or overlay semantics are invented.

The chain under test is:

```text
network-labs examples
  -> network-compiler
  -> network-forwarding-model
  -> network-control-plane-model
  -> network-renderer-nixos
  -> s-router-test live validation
```

## Ownership

- `network-*` repositories own schema, compiler behavior, forwarding/control-plane
  data, and renderer output.
- Nebula member materialization is tested as a standalone
  `network-renderer-nebula` CLI/service contract; this VM should not import that
  renderer directly while proving the base NixOS topology.
- `network-labs` owns reusable examples.
- `s-router-test` owns router VM/container materialization and live probes.
- `s-router-test-clients` owns client endpoint and DMZ service fixtures.
- Any local `s-router-test` helper that injects routes, firewall, delegated-prefix
  behavior, or overlay runtime policy is transitional glue and must be recorded in
  `regression.md` as wrong-layer work.

## Current Examples

The active tri-site examples are in the locked `network-labs` input:

- `examples/s-router-test-three-site`

Do not use `../../` or `file:` path inputs for the remote rebuild path. `s-sigma`
only sees the NixOS checkout and locked flake inputs.

## Required Scripts

Use the script wrappers instead of hand-rolled SSH quoting:

```bash
~/github/network-codex-agent/scripts/s-router-full-lab-rebuild-loop.sh
~/github/network-codex-agent/scripts/exec-on-remote.sh s-router-test <cmd> [args...]
~/github/network-codex-agent/scripts/exec-in-s-router-test-machine.sh <container> <cmd> [args...]
```

The rebuild loop syncs the NixOS tree to the launcher workspace, builds through
the locked flake chain, reboots `s-router-test`, unlocks the transient Nebula CA,
and runs live probes. Treat helper summaries critically; direct container checks
are still required before claiming production readiness.

## Review/Test Module Execution

Runtime-bound SMT and RaTM modules that depend on live NixOS substrate execute
here, not in `network-codex-agent`.

`network-codex-agent` may register the module, parse-check a reference fixture,
start the loop, and collect evidence. It does not own VLAN `4`, runtime bridges,
containers, nftables, DNS, or route behavior.

Required behavior for a harness-owned test runner:

- run the selected SMT/RaTM module inside the rebuilt `s-router-test` runtime;
- record exact command, container/node, source address, expected route/firewall
  behavior, and evidence artifact;
- fail if required VLANs, bridges, generated renderer artifacts, or runtime
  expectation files are missing;
- refuse to mark a row `OK` from a repo-local parse/build outside this runtime.
- delegate Nebula public endpoint, public IP, public ingress, and remote overlay
  return-route acceptance to the Hetzner harness, because this VM does not own
  the live public provider addresses.

For the fake PPPoE upstream module:

- VLAN `11` is the fake PPPoE provider-to-core handoff;
- VLAN `4` is the fake provider upstream/WAN side;
- fake downstream/client-side fixture segments must not use VLAN IDs `2`
  through `10`;
- packet behavior, nft counters, route selection, DNS behavior, and no-router-GUA
  checks are acceptance evidence only when collected from this runtime or a
  matching CLAB/Hetzner harness.

Nebula overlay/public-IP context:

- local `s-router-test` checks may prove rendered/provider material, service
  startup, local overlay interface state, and local route/firewall preflight;
- public endpoint reachability, public ingress, remote overlay return routes,
  and live public IP behavior must be proven by the Hetzner harness.

## Hostile IPv6 Target

The intended hostile IPv6 design is routed GUA, not NAT66:

- hostile clients receive SLAAC from `2a01:4f8:1c17:b337::/64`
- infrastructure hops do not receive addresses from that GUA prefix
- `b-router-access-hostile` advertises the prefix and has an on-link route back
  to the tenant
- `b-router-core-nebula` carries hostile public IPv6 toward the Hetzner
  validation host over Nebula
- Hetzner routes `2a01:4f8:1c17:b337::/64` back over Nebula with no IPv6 NAT

Current external validator:

- host role: `hetzner-nebula-prodtest-01`
- user: `root`
- NixOS flake host: `s-router-hetzner-anywhere`
- runtime addresses and delegated prefixes are generated from
  `network-codex-agent/scripts/s-router-test-hetzner-spawn.sh` before
  `nixos-anywhere` evaluates the host
- expected hostile return route: delegated hostile GUA prefix via
  `fd42:dead:beef:ee::2 dev nebula0`

The validator is disposable. Manual service, firewall, or route installation on
the Debian rescue/base image is not part of the contract; the NixOS host config
must own those settings before live validation starts.

## Production Gate

Do not call this production-ready until all of these are live-verified on the
returned host generation:

- local build and rebuild loop pass through locked inputs
- expected containers are running
- access DNS works and restricted tenants do not leak to public DNS
- lane-preserving route selection is proven with live `ip route get`
- Nebula services are active and peer reachability works where intended
- hostile GUA egress and return traffic work through Hetzner without NAT66
- site-c service reachability and storage overlay checks pass

If any item is unverified or broken, update `regression.md` instead of reporting
success.
