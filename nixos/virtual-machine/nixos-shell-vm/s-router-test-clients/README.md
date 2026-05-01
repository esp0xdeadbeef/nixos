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

- site-a admin/client DHCP endpoints
- branch and hostile DHCP endpoints
- site-c home, NAS, printer, and streaming endpoints
- DMZ service fixtures for Nebula, WireGuard, and HTTP

## Boundary

Keep this box client-focused:

- no Nebula bootstrap generation
- no router route/rule injection
- no hostile GUA router overrides
- no CPM or renderer contract reinterpretation
- no copied router container modules from `s-router-test`

If an endpoint needs new policy to work, patch the owning `network-*` layer or
the router-side harness first, then keep this box as the client consumer.
