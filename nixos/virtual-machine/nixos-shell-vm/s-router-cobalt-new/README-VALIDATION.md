# s-router-cobalt-new validation papertrail

This note records the cobalt-new route investigation and the safe rollout
procedure. `s-router-cobalt-prod` is the live cobalt router and is not part of
this test; do not stop or reconfigure it for a candidate test without a planned
maintenance window and an explicit rollback path.

## What was wrong

The admitted `s-router-cobalt-new` image built on 2026-10-27
(`/nix/store/a6q4bcn168lxkh8gdrh5cd8kqwkmmsp8-nixos-vm`) booted with all 15
containers and no failed units, but had no usable routes:

- tenant-source lookup: `RTNETLINK answers: Network is unreachable`;
- `clients-vpn` to Tang (`fd42:dead:beef:290::10`): `Network is unreachable`;
- `clients-vpn` to IPv6 Internet: `Network is unreachable`;
- `clients-vpn`/`access-clients` to IPv4 Internet: 100% loss;
- `core` to IPv4/IPv6 Internet: `Network is unreachable`;
- no default routes were present in the access, policy, or core namespaces.

The manager trial correctly rolled back:

```text
prod_active=active new_active=inactive
```

This was a stale-image failure, not evidence against the current source.

## Current source evidence

The latest cobalt pipeline was evaluated without a router restart:

- `access-clients-vpn` CPM route: `0.0.0.0/0 via 10.1.0.3`,
  `policyOnly=true`, `reason=policy-derived-default`, lane `uplink=onyx`;
- `access-clients` has the corresponding `0.0.0.0/0 via 10.1.0.1`;
- `core-vpn-onyx`/`core-vpn-opal` have `overlay-onyx`/`overlay-opal`
  defaults and NAT66 forwarding;
- the latest `s-router-nixos` image (`/nix/store/gq6...-nixos-vm`) was built,
  rolled out on s-sigma, and shows real per-container route tables:
  `access-local 10.54.46.1/24`, `access-recursive 10.54.45.1/24`,
  `policy` defaults via `up0`/`down0`/`down1`, and `core-primary` default via
  the lab WAN. No failed units.

The `systemd.network.networks.*.dhcpConfig` error seen while dumping the full
NixOS option tree is a nixpkgs removed-option diagnostic, not a build blocker:
the latest `s-router-nixos` image builds and boots with the same renderer.

## Candidate procedure

Work from the main `nixos` checkout that the operator rsyncs to s-nodus. Build
the latest image, then use the manager's candidate/rollback path:

```bash
sudo vm-update s-router-cobalt-new /home/deadbeef/github/nixos
```

Do not start a candidate and the production router together: the generated
unit's `Conflicts` key is currently in the wrong systemd section, so the
one-at-a-time rule must be enforced by the trial script. The safe sequence is:
stop prod, register/start new, verify QGA health, hold for the test window,
then stop new and start prod. A detached `systemd-run` trial with a 20-minute
failsafe is required so the operator is not cut off by the WAN flap.

## Acceptance checks for the candidate

1. `s-router-cobalt-new` boots with 15 containers and no failed units.
2. `access-clients` obtains DHCP and can egress via `core`.
3. `access-clients-vpn` obtains DHCP and can reach Tang and the Internet via
   the onyx/opal overlay path.
4. `core`, `policy`, `downstream-selector`, and `upstream-selector` have the
   expected explicit routes; no accidental default route is emitted on an
   access node.
5. Rollback restores `s-router-cobalt-prod` and Internet access.

The s-router-nixos DHCP test client (see its README) is the isolated harness
for steps 2/3 before touching cobalt.
