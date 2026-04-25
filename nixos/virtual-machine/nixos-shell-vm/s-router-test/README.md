# `s-router-test`

This lab is a single-VM integration harness for the `network-*` pipeline:

```text
intent
  -> network-compiler
  -> network-forwarding-model
  -> network-control-plane-model
  -> network-renderer-nixos
  -> s-router-test runtime validation
```

The goal is not just to boot a pretty demo. The goal is to keep one place where
multi-WAN, multi-enterprise, DMZ ingress, and overlay direction can be validated
without changing the architectural model.

## Canonical Model

`s-router-test` is now a renderer consumer, not the canonical home of the
active topology model.

The ownership rule is explicit:

- `network-*` repositories are responsible for emitting the control-plane and
  renderer-consumable schemas/runtime plans
- `s-router-test` is responsible only for consuming those emitted results and
  materializing disposable emulated nodes around them for validation
- if `s-router-test` starts inventing schema, route policy, overlay ownership,
  or runtime semantics locally, that is a regression in the wrong layer

The authoritative examples live in the locked `network-labs` input:

- BGP:
  [examples/tri-site-dual-wan-overlay-integration-bgp](/home/deadbeef/github/network-labs/examples/tri-site-dual-wan-overlay-integration-bgp)
- static:
  [examples/tri-site-dual-wan-overlay-integration-static](/home/deadbeef/github/network-labs/examples/tri-site-dual-wan-overlay-integration-static)

`s-router-test` consumes those examples directly from
[default.nix](/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/default.nix:1):

- intent:
  `inputs.network-labs/examples/tri-site-dual-wan-overlay-integration-bgp/intent.nix`
- inventory:
  `inputs.network-labs/examples/tri-site-dual-wan-overlay-integration-static/inventory-base.nix`

Both canonical examples have been compiled through both consumers:

- `inventory-nixos.nix` through `network-renderer-nixos`
- `inventory-clab.nix` through `network-renderer-containerlab-linux-backend`

## Recommended Modeling Pattern

For a scalable setup, keep responsibilities split like this:

### `intent.nix`

`intent.nix` should carry only architecture and policy semantics:

- enterprises
- sites
- tenant ownership
- services exposed as communication-contract services
- WAN policy
- inter-site policy
- overlay intent via `transport.overlays`

Example shape:

```nix
transport.overlays = [
  {
    name = "east-west";
    peerSite = "other-enterprise.site-b";
    terminateOn = "s-router-core";
    mustTraverse = [ "policy" ];
  }
];
```

The policy side should reference the overlay as an external:

```nix
{
  from = { kind = "tenant"; name = "client"; };
  to = { kind = "external"; name = "east-west"; };
  trafficType = "any";
  action = "allow";
}
```

### `inventory.nix`

`inventory.nix` should carry realization and control-plane specifics:

- host uplinks and bridges
- runtime node placement
- BGP vs static mode
- overlay provisioning data under `controlPlane.sites.<enterprise>.<site>.overlays`
- explicit endpoint addresses for exposed services

For Nebula-style overlays, the CPM-side provisioning block is the right place to
record:

- provider name
- overlay IPAM prefixes
- node overlay addresses
- lighthouse hints

That keeps overlay addressing owned by the control-plane stage rather than buried
inside ad hoc VM scripts.

## Runtime Nebula Direction

Right now `s-router-test` uses a transitional runtime bootstrap:

1. the host generates Nebula runtime profiles under `/persist/nebula-runtime`
2. those profiles are bind-mounted into the relevant containers
3. the container `nebula-runtime` service waits for the profile and then starts

This is intentionally a lab bridge. The long-term direction should be:

- CPM emits overlay provisioning data
- renderer emits runtime consumers for that provisioning data
- a dedicated secret/cert library handles CA-protected signing

The lab should stop hardcoding overlay node names and addresses once that path is
fully integrated.

## Secret Generation Library Direction

The scalable design is a small library or module with these properties:

- CA private material is encrypted at rest
- the CA is only available after explicit manual unlock
- the unlock can be tied to LUKS, an offline removable secret, or manual `sops`
  decryption into `/run/keys`
- host-cert generation is idempotent and happens only after the CA is available
- runtime consumers never need the CA key, only signed node certs

A good interface would look like:

```nix
{
  overlays.east-west = {
    provider = "nebula";
    ca = {
      source = "/persist/secure/nebula-ca.age";
      unlockCommand = "systemctl start nebula-ca-unseal";
    };
    nodes = {
      s-router-core-isp-b = { groups = [ "core" ]; };
      b-router-core = { groups = [ "branch" ]; };
      nebula01 = { groups = [ "lighthouse" ]; };
    };
  };
}
```

The important rule is:

- the CA unlock is operator-controlled
- node cert distribution is automated after unlock

That matches the security model you described: no silent background CA handling if
the root secret is not explicitly unsealed.

## Current CA Flow

The current test-VM implementation now follows that rule closely enough for this
lab:

1. the public CA stays on disk at `/persist/nebula-runtime/pki/ca.crt`
2. the private CA key stays encrypted at rest at `/persist/nebula-runtime/pki/ca.key.enc`
3. the host does not carry a persistent `sops` secret for the decrypt credential
4. an operator or external bot must supply the decrypt credential transiently
   over an active SSH session into `/run/keys/nebula-ca-passphrase`
5. `nebula-ca-unseal.service` unseals the CA only into `/run/nebula-runtime/unsealed/ca.key`
6. `nebula-profile-bootstrap.path` notices that `/run` key and starts issuance
   automatically
7. after issuance, the transient `/run` passphrase and unsealed key are deleted

For the disposable test VM, the helper entrypoint is:

- [scripts/s-router-test-nebula-ca-unseal.sh](/home/deadbeef/github/scripts/s-router-test-nebula-ca-unseal.sh:1)

and the rebuild loop already calls it after the host returns:

- [scripts/s-router-test-rebuild-loop.sh](/home/deadbeef/github/scripts/s-router-test-rebuild-loop.sh:1)

That keeps the decrypt credential off-host except during the explicit unlock
window while still letting the test harness reissue certs automatically after
the operator or bot has authenticated.

## Remote Helpers

For disposable live validation nodes, use:

- [scripts/exec-on-remote.sh](/home/deadbeef/github/scripts/exec-on-remote.sh:1)

It takes a host plus command/arguments and forwards them over SSH without
hand-writing nested shell quoting each time.

Example:

```bash
./scripts/exec-on-remote.sh root@46.224.173.254 ip -6 route
```

That is useful for the temporary Hetzner validation box and other disposable
live probes where ad hoc SSH quoting was getting in the way of repeatable
checks.

For commands inside `s-router-test` containers, use:

- [scripts/exec-in-s-router-test-machine.sh](/home/deadbeef/github/scripts/exec-in-s-router-test-machine.sh:1)

Example:

```bash
./scripts/exec-in-s-router-test-machine.sh hostile-node01 ip -6 route get 2606:4700:4700::1111
./scripts/exec-in-s-router-test-machine.sh b-router-core ip rule
```

That helper already does the correct host-side `sudo systemd-run --machine
--pipe` invocation, so the validation workflow does not need to rediscover the
right transport each time.

## Current Lab Direction

The active multi-enterprise profile is designed to validate this target shape:

- enterprise A
  - dual WAN
  - DMZ tenant
  - DMZ Nebula lighthouse service
  - overlay termination intent on a core node
- enterprise B
  - single WAN
  - branch tenant
  - overlay termination intent on its core node
  - internet egress plus explicit east-west policy allowance

The lab is still a renderer-validation environment first. If a workaround starts
replacing renderer behavior instead of exercising it, that is a regression in
test quality.

## Hostile IPv6 Direction

The intended hostile IPv6 design is:

- hostile clients receive real GUA from a delegated `/64`
- routers and intermediate hops do not receive those client GUAs
- public IPv6 exit is routed, not NAT66
- the public-exit path is owned by the modeled router/core path, not by a
  client-local overlay runtime

For the current disposable external validator, a routed hostile `/64` is now
available from Hetzner:

- `2a01:4f8:1c17:b337::/64`

That means the previous “this VPS cannot possibly do non-NAT hostile IPv6”
statement is no longer true as a hard external limitation. The remaining work is
to model and validate the routed-prefix path correctly through the `network-*`
chain and the disposable VPS configuration.

Current verified VPS state:

- `eth0` carries:
  - `2a01:4f8:c013:628b::1/64`
  - `2a01:4f8:1c17:b337::1/128`
- the hostile delegated `/64` is routed back over Nebula:
  - `2a01:4f8:1c17:b337::/64 via fd42:dead:beef:ee::30 dev nebula0`
- IPv6 NAT66 is not present there

Current returned-host failure:

- `hostile-node01` gets SLAAC GUA addresses from `2a01:4f8:1c17:b337::/64`
- hostile DNS works
- but public IPv6 still times out on the current returned host because route
  selection still prefers the client-local overlay table:
  - `ip -6 route get 2606:4700:4700::1111`
  - `via fd42:dead:beef:ee::254 dev nebula1 table 100 src fd42:dead:beef:ee::30`

## Production Gate

`s-router-test` is only production-ready when all of these are live-verified on
the returned host generation through the locked flake chain:

- local build gate passes
- rebuild loop returns a live host and `s88-network-validation-status` is ready
- access-router DNS works for all modeled tenants and does not self-forward
- direct public DNS leaks are blocked from restricted tenant contexts
- lane preservation is correct in live kernel routing, not just rendered files
- overlay traffic selects the intended path from the correct container contexts
- hostile egress still exits via the modeled Hetzner path on both IPv4 and IPv6
- `site-c` local-name resolution and intended east-west/service reachability work
- `site-c` discovery works where intended
- `site-c` storage overlay reaches the Hetzner storage lighthouse without giving
  NAS or printer general internet access
- hostile clients receive delegated global IPv6 space where required; transit
  routers and intermediate hops must not receive those client GUAs

Anything less belongs in `regression.md`, not in a “production-ready” claim.

## Current Site-C Target

`site-c` is intended to model:

- `mgmt`
- `home-users`
- `printer`
- `nas`
- `streaming`
- `iot`

with these security constraints:

- `home-users` may reach `printer`, `nas`, and `streaming`
- `printer` and `nas` must not have general internet egress
- `printer` local names must resolve both ways via the modeled site DNS path
- `streaming` discovery should be visible from `home-users`, not the other way
  around
- `site-c-storage` is an overlay-only storage path, not a reason to route NAS or
  printer traffic over generic WAN defaults

The long-term design split is still:

- control-plane / renderer emit desired overlay runtime state
- `s-router-test` materializes that state in this specific lab

For the multi-site direction beyond this VM harness, see:

- [MULTI_SITE_OVERLAY_PLAN.md](/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/MULTI_SITE_OVERLAY_PLAN.md:1)
