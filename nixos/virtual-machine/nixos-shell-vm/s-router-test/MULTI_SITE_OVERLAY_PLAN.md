# Multi-Site Overlay Runtime Plan

This note describes how to take the current `s-router-test` Nebula work and
turn it into a model that scales beyond one VM and one disposable VPS.

The intended real scope is:

- one physical site at home
- one physical site at parents' home
- one disposable VPS or relay/lighthouse site

The main design rule is:

- control-plane and renderer emit desired overlay runtime state
- deployment or lab harness decides how to materialize that state

That means the renderer should emit a normalized runtime plan, but it should not
contain SSH-to-VPS behavior, binary downloads, remote `systemctl` mutation, or
manual CA retrieval logic.

## Problem With The Current Single-Host Shape

The current lab still carries some transitional logic that starts from a local
host-centric view:

- render one host
- inspect `renderedHostNetwork.sites.<enterprise>.<site>.overlays`
- reconstruct Nebula state locally
- then bolt a Hetzner bootstrap onto it

That is good enough for a temporary integration harness, but it does not scale
cleanly to:

- multiple physical routers
- multiple independently managed sites
- one or more relay/lighthouse nodes that are not rendered like the main site
- operator-controlled CA material

The core issue is that parsing by `current host -> local site subtree` is the
wrong abstraction once an overlay spans several places.

## Correct Parsing Unit

Parse by:

- `overlay -> participating runtime nodes across all sites`

not by:

- `host -> local overlay fragments`

This lets the system answer:

- which overlay exists
- which nodes participate
- which node is the lighthouse
- which endpoints are underlay addresses
- which routes/groups belong to each member
- which parts are model state vs deployment glue

## Layer Split

The clean split should be:

1. `intent.nix`
   - policy and architectural semantics only
2. `inventory.nix`
   - realization facts and runtime-node placement
3. renderer output
   - normalized desired overlay runtime state
4. deployment or harness logic
   - copy files, unseal CA, issue certs, start services

### `intent.nix`

`intent.nix` should describe:

- sites
- tenants
- services
- communication contracts
- overlay purpose
- which traffic is allowed over which overlay

It should not describe:

- SSH users
- remote file paths
- how a VPS gets provisioned
- where the Nebula binary is downloaded from

### `inventory.nix`

`inventory.nix` should describe:

- which runtime nodes exist at each site
- which uplinks/underlay endpoints they have
- which site may host lighthouses or relays
- which routing mode is active
- explicit overlay provisioning facts

It should still avoid deployment glue such as:

- `scp` destinations
- ad hoc shell scripts
- remote package install steps

### Renderer Output

The renderer should emit deterministic desired overlay runtime state.

That state should be sufficient to answer:

- what overlay exists
- what the CA namespace is called
- who the lighthouse is
- which endpoints it should advertise
- which node gets which overlay addresses
- which groups a node belongs to
- which unsafe routes a node should install or expose
- which runtime service/interface names should exist

### Deployment Or Harness Logic

This layer should decide:

- how to reach the VPS
- where to store certs and profiles
- how CA material is unlocked
- how to copy profiles onto a remote node
- how to start the remote Nebula service

That is where `s-router-test` still has temporary glue today.

## Recommended Runtime Plan Shape

The runtime plan should look like a global overlay index with a per-node view.

Conceptually:

```nix
overlayRuntime.nebula = {
  overlays.east-west = {
    type = "nebula";

    ca = {
      name = "homelab-east-west";
    };

    lighthouse = {
      node = "vps-nebula01";
      port = 4242;
      endpoints = [
        "46.224.173.254:4242"
        "[2a01:4f8:c013:628b::1]:4242"
      ];
    };

    nodes.home-core = {
      site = "home";
      overlayAddresses = [
        "100.96.10.10/24"
        "fd42:dead:beef:ee::10/64"
      ];
      groups = [ "home" "core" ];
      unsafeRoutes = [ ];
      service = {
        name = "nebula-runtime";
        interface = "nebula1";
      };
    };

    nodes.parents-core = {
      site = "parents";
      overlayAddresses = [
        "100.96.10.20/24"
        "fd42:dead:beef:ee::20/64"
      ];
      groups = [ "parents" "core" ];
      unsafeRoutes = [ ];
      service = {
        name = "nebula-runtime";
        interface = "nebula1";
      };
    };

    nodes.vps-nebula01 = {
      site = "vps";
      overlayAddresses = [
        "100.96.10.254/24"
        "fd42:dead:beef:ee::254/64"
      ];
      groups = [ "lighthouse" "relay" ];
      unsafeRoutes = [ ];
      service = {
        name = "nebula-runtime";
        interface = "nebula1";
      };
    };
  };
};
```

This is the right level for renderer output because it is:

- derived from model state
- deterministic
- deployment-neutral

## Global And Per-Node Views

The runtime plan should provide two useful views.

### Global Overlay View

Used for:

- CA naming
- lighthouse selection
- overlay-wide IPAM
- membership and cert planning

Example questions:

- which nodes are in `east-west`
- which node is the lighthouse
- which public endpoints should members dial

### Per-Node Runtime View

Used for:

- local service generation
- profile emission
- systemd unit creation
- interface naming

Example questions:

- what profile should `home-core` run
- what routes should `parents-core` advertise or consume
- what service/interface names should exist on `vps-nebula01`

## Suggested Inventory Model

The inventory should carry explicit runtime-node participation, not force a lab
to reverse-engineer it later.

An appropriate shape is:

```nix
controlPlane.sites.home.runtimeNodes.home-core = {
  kind = "router";
  underlay = {
    dynamic = true;
  };
  overlays.east-west = {
    role = "member";
    groups = [ "home" "core" ];
  };
};

controlPlane.sites.parents.runtimeNodes.parents-core = {
  kind = "router";
  overlays.east-west = {
    role = "member";
    groups = [ "parents" "core" ];
  };
};

controlPlane.sites.vps.runtimeNodes.vps-nebula01 = {
  kind = "lighthouse";
  publicEndpoints = [
    "46.224.173.254"
    "2a01:4f8:c013:628b::1"
  ];
  overlays.east-west = {
    role = "lighthouse";
    groups = [ "lighthouse" "relay" ];
  };
};
```

The important property is that the inventory states who participates and what
kind of node it is, without embedding shell-level deployment details.

## How This Maps To The Current API

`network-renderer-nixos` already has the start of this shape:

- `api.overlayRuntime.nebulaPlan`

and `s-router-test` already consumes it in:

- [default.nix](/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/default.nix:97)

That means the architectural direction is already correct. The remaining work is
to strengthen the emitted plan so that the lab consumes a complete runtime plan
instead of rebuilding parts of it from local assumptions.

## What Must Not Move Upstream

The following should stay outside the renderer:

- `root@46.224.173.254`
- `/persist/nebula-runtime`
- `scp` to the VPS
- downloading the Nebula release binary
- remote `iptables` edits
- remote `systemctl enable --now ...`
- how operators unlock or retrieve the CA

Those are deployment/harness concerns, not renderer semantics.

## CA Handling For Real Deployments

The real design for home + parents + VPS should require:

- CA encrypted at rest
- explicit operator unlock
- manual or operator-approved retrieval before cert issuance
- no silent background access to the CA key

Recommended split:

- renderer emits CA namespace and node cert requirements
- a secret/cert library manages encrypted CA storage and manual unseal
- deployment logic consumes signed certs, not the CA key itself

Conceptually:

```nix
overlayRuntime.nebula.overlays.east-west.ca = {
  name = "homelab-east-west";
  secretRef = "nebula-ca-east-west";
};
```

Then the deployment side can say:

- unlock `nebula-ca-east-west`
- sign requested nodes
- publish node certs and profiles

without pushing CA mechanics into the renderer.

## Recommended Migration Path

1. Keep the current `api.overlayRuntime.nebulaPlan` entrypoint.
2. Extend it so it emits the full runtime plan needed by multi-site consumers.
3. Make `s-router-test/modules/nebula-bootstrap.nix` consume that plan instead
   of rebuilding overlay structure from local site trees.
4. Keep Hetzner or future VPS bootstrap logic local to the harness.
5. Once stable, promote the full active `s-router-test` example into
   `network-labs/examples` as a canonical integration test.

## Real-World Shape For Home + Parents + VPS

The practical deployment model should be:

- `home`
  - one or more real routers
  - tenant/access networks
  - optional storage or printer nodes
- `parents`
  - one or more real routers
  - tenant/access networks
- `vps`
  - lighthouse/relay only
  - no special semantic status beyond being another site with a public underlay

That means the system should scale from:

- one VM harness

to:

- two physical sites plus one VPS

without changing the overlay model, only the deployment/materialization logic.

## Short Version

If this work is going to survive beyond `s-router-test`, the parser must think
in terms of:

- global overlays
- participating runtime nodes
- explicit per-node runtime plans

and not:

- one host reconstructing overlay meaning from its local subtree

That is the difference between a useful lab and a deployable architecture.
