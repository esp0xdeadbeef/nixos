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
- branch and hostile DHCP endpoints
- DMZ service fixtures for Nebula, WireGuard, and HTTP

Site-C access routers are realized on the Hetzner validation host in the current
lab inventory. Site-C endpoint fixtures must live with that modeled access
fabric, or be introduced through explicit inventory/model placement, before
this client box materializes them.

## Boundary

Keep this box client-focused:

- no Nebula bootstrap generation
- no router route/rule injection
- no hostile GUA router overrides
- no CPM or renderer contract reinterpretation
- no copied router container modules from `s-router-test`

If an endpoint needs new policy to work, patch the owning `network-*` layer or
the router-side harness first, then keep this box as the client consumer.
