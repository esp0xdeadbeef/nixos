# network-* validation: current state and blockers

## Green

network-compiler, network-forwarding-model (82/82), network-labs,
network-realization-model, network-realization-schema,
network-renderer-containerlab-linux-backend, network-renderer-nebula,
network-renderer-wireguard and network-renderer-access-endpoint-nixos: latest
CI run success. network-control-plane-model: **242 PASS / 0 FAIL** and CI
success (all 11 previously red GAMP cases fixed). network-renderer-nixos:
24 PASS / 2 FAIL (the two cases below). nixos: `nix flake check --no-build`
passes; the dispatched "Flake.lock: update and push" and "Network model check"
runs succeed.

## Fixed in this work

Control plane: FS-540 named-core DNS endpoints, requester-lane resolver
reachability, policy-lane and ingress policy-table defaults, overlay endpoint
host identities, overlay DNS ingress transit, delegated peer return routes on
the WAN core (`dst = null` records were filtered out), FS-410 NAT66 authority,
MSS clamp from modeled MTU, FS-770 canonical-profile equivalence, FS-420
translation authority, FS-380 selection-derived lane set, FS-460 overlay return
next hops and FS-315 lane defaults, FS-720 checker row id, FS-800 PPPoE/PD
contract cases, FS-970 reservation-source conflict, and removal of the last
name-inference in the CPM. Forwarding model: tenant-set default attribution and
FS-315 generic-default lane gating. Renderer: canonical route-table mapping,
source-scoped deny-by-default and policy-table parity cases, plus the transit
endpoint return case. nixos: removal of the obsolete nixos-network-compiler
input and of brave. network-realization-schema: wrapped-CPM validation.

## Blocked

- network-renderer-nixos `test-overlay-core-local-hostile-return-routes.sh`:
  its private tri-site fixture models the overlay as a routed core uplink that
  carries specific prefixes, which the forwarding model now rejects
  (`overlay-core-uplink-dedicated`). Migrating it means re-expressing the
  imported prefixes as `transport.overlays.<name>.prefixes.imported` and
  re-deriving the host inventory's overlay lane ports — i.e. authoring a
  canonical tri-site example (URS assigns intent to the user; the attempts are
  captured in the renderer `docs/blockers.md`).
- network-renderer-nixos `test-runtime-origin-loopback-egress-render.sh`:
  asserts the pre-FS-315 model (overlay core installs a generic default with
  `PreferredSource` for the router loopback). The current model renders the
  runtime-origin source rule on the overlay core ingress pointing at the overlay
  lane table, while the modeled egress defaults live in the per-access underlay
  lane tables and the overlay core has no main-table default (FS-315). Whether
  that source selector must bind the egress lane table is an FS-550
  route-selection-authority decision owned by the control plane, not a renderer
  assertion; the renderer may not invent a table the CPM did not model.

Neither blocker is "pre-existing and therefore ignorable": both are documented
with the owning spec item and the concrete next step in
`network-renderer-nixos/docs/blockers.md`.
