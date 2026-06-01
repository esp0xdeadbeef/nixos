# `s-router-clab`

`s-router-clab` is the CLAB runtime harness for model/render validation. It
owns CLAB container materialization, CLAB bridges, CLAB route/firewall/DNS
probes, and CLAB-specific CMC/RaTM module tests before FAT evidence is accepted.

## Review/Test Module Execution

Runtime-bound CMC/RaTM tests that target CLAB execute here, not as repo-local
parse/build checks in `network-codex-agent`.

Required behavior for CLAB-scoped module tests:

- run the selected CMC/RaTM module test inside the rebuilt `s-router-clab`
  runtime;
- record exact command, container/node, source address, expected route/firewall
  behavior, and evidence artifact;
- fail if required CLAB bridges, VLANs, generated renderer artifacts, or runtime
  expectation files are missing;
- refuse to mark a row `OK` from a repo-local parse/build outside this runtime.

For the fake PPPoE upstream module:

- VLAN `11` is the fake PPPoE provider-to-core handoff;
- VLAN `4` is the fake provider upstream/WAN side;
- fake downstream/client-side fixture segments must not use VLAN IDs `2`
  through `10`;
- CLAB route/firewall/DNS and no-router-GUA behavior are acceptance evidence
  only when collected from this runtime or an equivalent owning harness.

Nebula overlay/public-IP context:

- local CLAB checks may prove renderer output, local service wiring, local
  routes, local firewall rules, and local leak-prevention preflight;
- public endpoint reachability, public ingress, remote overlay return routes,
  and live public IP behavior must be proven by the Hetzner harness.
