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

## Profile Layout

Current profile :

- `dual-wan-branch`
  Two enterprises in one VM:
  - enterprise A: dual uplink, DMZ, overlay termination intent
  - enterprise B: single uplink, branch-side overlay termination intent

The active model now lives directly in the root files:

- [intent.nix](/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/intent.nix:1)
- [inventory.nix](/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/inventory.nix:1)

Compatibility wrappers still exist for mode selection and older references:

- [bgp-inventory.nix](/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/bgp-inventory.nix:1)
- [static-inventory.nix](/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/static-inventory.nix:1)

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
