# `s-router-test-clients`

`s-router-test-clients` owns the endpoint/client half of the `s-router-test`
validation topology. It should contain tenant clients, DMZ service fixtures, and
small endpoint helpers only.

It must not own router behavior, overlay materialization, public-exit policy,
delegated-prefix routing, or renderer semantics. Those belong in the
`network-*` repos and the router-side `s-router-test` harness consumes the
locked output.

## Containers

The box currently materializes:

- nixos admin/client DHCP endpoints
- `s-sigma` as a DHCP-only mgmt-side hypervisor fixture
- CLAB endpoint fixtures for the modeled tenant clients on the shared lab VLANs
- branch and hostile DHCP endpoints
- DMZ service fixtures for Nebula, WireGuard, and HTTP

Endpoint fixtures must be derived from `intent.nix`, resolved inventory, and
renderer runtime targets. Adding a site endpoint here must not copy router
behavior or infer topology from names.

`s-sigma` is a hypervisor/build host fixture, not an access-node service. It is
attached to the mgmt bridge and receives its address from DHCP like the real
network. Admin reachability must come from the modeled admin-to-mgmt policy, not
from local route or firewall shortcuts in this box.

## Boundary

Keep this box client-focused:

- no Nebula bootstrap generation
- no router route/rule injection
- no hostile GUA router overrides
- no CPM or renderer contract reinterpretation
- no copied router container modules from `s-router-test`

If an endpoint needs new policy to work, patch the owning `network-*` layer or
the router-side harness first, then keep this box as the client consumer.
