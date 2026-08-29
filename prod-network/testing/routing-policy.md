# Routing policy — cobalt / neon

Multi-site routing and segmentation design. It supersedes the original
`s-router-policy-only/ROUTING-POLICY.md` (VLAN-number scheme) with a
name-based model: the plane is encoded in the DNS zone, never in the VLAN
number. Sites share one namespace; the site is a routing property, not part
of any name.

## Principles

1. **Plane = name.** The security boundary is expressed as a DNS zone
   (`mgmt.home.arpa`, `dmz.home.arpa`, …), not as a VLAN number. VLAN numbers
   are site-local implementation detail.
2. **One shared namespace, RFC 8375 root.** The namespace root is `home.arpa`
   (the IETF-designated home-networking domain). Unregistered pseudo-TLDs such
   as `.lan`, `.home`, `.local` are avoided: they can collide with a future
   real delegation.
3. **One zone per plane.** Each plane gets its own subdomain of `home.arpa`.
   Hostnames are globally unique; the site never appears in an FQDN.
4. **Reserve, instantiate lazily.** The full plane taxonomy is reserved here
   (names + spare VLAN ranges). A plane becomes a real VLAN + zone + policy
   relations only when the first device lands in it.
5. **`vlan2` is legacy.** It is a holding pen: split it, do not grow it.
6. **Policy decides recursion.** DNS recursion permission is a
   `recursiveDnsIntent` relation enforced by the policy node. The overlay is
   transport only, never a recursion authority.
7. **Policy decides the search domain.** The DHCP search domain (option 15) is
   derived from the resolver's allowed namespaces (`localDnsSharingIntent`),
   not hardcoded.
8. **No zone transfers.** Topology is intent-driven and static; DNS links are
   predetermined (stub/forward zones) and derived from the policy relations.

## Plane taxonomy

VLAN ranges are *reserved*, not modeled. A range is instantiated only when a
device actually needs it.

| plane        | DNS zone              | trust        | reserved VLAN | status                          |
| ------------ | --------------------- | ------------ | ------------- | ------------------------------- |
| control      | `mgmt.home.arpa`      | absolute     | 10–19         | reserved — split out of `vlan2` |
| service      | `svc.home.arpa`       | limited      | 20–29         | live                            |
| endpoint     | `clients.home.arpa`   | untrusted    | 30–39         | live                            |
| corp         | `corp.home.arpa`      | semi-hostile | 40–49         | reserved                        |
| iot          | `iot.home.arpa`       | hostile      | 50–59         | live                            |
| dmz          | `dmz.home.arpa`       | exposed      | 60–69         | live                            |
| lab          | `lab.home.arpa`       | hostile      | 70–79         | reserved                        |
| observability| `obs.home.arpa`       | limited      | 80–89         | reserved                        |
| unlock       | `unlock.home.arpa`    | hostile      | 90–99         | live (Tang-only, cobalt)        |
| transit      | `mesh` (overlay)      | neutral      | 100–199       | live (overlay)                  |
| wan          | —                     | unknown      | 1000+         | live                            |

### Trust anchors (normative)

- Control plane is authority. If it grants trust, it lives in `mgmt.home.arpa`.
- Service plane consumes trust; it does not define it.
- Endpoints never reach control directly (bastion/jump only).
- IoT reaches only WAN plus explicitly pinned services.
- DMZ reaches inward only through explicit backends.
- Lab is assumed compromised by design.
- Transit carries routers only: no RA/DHCP/mDNS, `/31` IPv4, `/127` IPv6.
- Unlock is a Tang-only access plane for stage-1 NBDE. Its PSK is shared in
  the repo/SOPS, so it is treated as hostile: DHCP is the only fabric service
  it receives, and its sole egress is the `tang` service (tcp/7500) on `svc`.
  No WAN, no recursion, no path to other planes.

## VPN egress (onyx)

The endpoint plane has two egress paths:

| tenant        | subnet         | VLAN | egress                    |
| ------------- | -------------- | ---- | ------------------------- |
| `clients`     | `10.2.30.0/24` | 30   | WAN (provider)               |
| `clients-vpn` | `10.2.31.0/24` | 31   | onyx overlay               |

- `clients-vpn` egresses through the onyx WireGuard tunnel
  (terminated on `core-vpn-onyx`) instead of the WAN. Its traffic is SNAT'd to
  the onyx egress ULA pool, so the site's public WAN address and WAN DNS are
  never used for this plane.
- IPv4: masquerade on `overlay-onyx` for `10.2.31.0/24`. IPv6: NAT66
  masquerade for `fd42:dead:beef:231::/64` (the clients-vpn ULA); the source
  is rewritten to the WireGuard tunnel address so onyx routes it. Both are
  modeled in the inventory `nat` block (no explicit `toAddress` — the
  masquerade uses the tunnel address).
- The onyx underlay is `iot-srv` (VLAN 51). That carries only the WG
  handshake/transport to the onyx endpoint — never client egress.
- `clients-vpn` recursion is pinned through the tunnel (no WAN resolver leak),
  see the DNS section below.

## DNS recursion / leak boundary (onyx)

The clients-vpn DNS chain is modeled in `recursiveDnsIntent` as an explicit
second resolver so its recursion egresses through the tunnel, not the WAN:

- Service `onyx-dns` with `providerNode = core-vpn-onyx` (addresses from the
  node's loopback model; the relation resolves to the `up-sel` p2p `10.1.0.14`
  / `fd42:dead:beef:2000::e`).
- Relation `allow-clients-vpn-to-onyx-dns` (tenant → service) and
  `allow-onyx-dns-to-onyx` (service → external `uplinks = [ "onyx" ]`).
- Binding `clients-vpn-dns` → `onyx-dns` with
  `resolverPath = [ access-clients-vpn downstream-selector policy upstream-selector core-vpn-onyx ]`
  and `egressSurface.uplinks = [ "onyx" ]`.

The core-vpn-onyx unbound runs in iterative mode (no forward zone); the CPM
`dnsEgressPolicy` selects the `overlay-onyx` interface, and the renderer marks
DNS output (`fwmark` = the selected policy table) so it routes out the tunnel
instead of the underlay. Chain:

```
client → access 10.2.31.1 (unbound) → core-vpn-onyx 10.1.0.14 (unbound, iterative)
       → overlay-onyx → onyx DNS
```

### Client-side (l-portal)

l-portal's USB Ethernet (`enu1u1`) is a plain DHCP/SLAAC client of whichever
cobalt access VLAN the switch port lands on — VLAN 31 `clients-vpn` for the
onyx egress test, VLAN 30 `clients` otherwise. NetworkManager owns `enu1u1`
outright: the hardcoded `cobalt-vpn` / `cobalt-clients` NM profiles and their
source-route rules were dropped in favour of default DHCP/SLAAC behaviour, so
no client-side routing config is needed.

The USB's DHCP/SLAAC comes only from cobalt (address `10.2.31.x` / ULA
`fd42:dead:beef:231::/64`, default via `10.2.31.1`/`fe80::…`, DNS
`10.2.31.1` + `fd42:dead:beef:231::1`); no home-router DNS is pushed. If the
client also has a WiFi connection, its resolver ordering is a client-side
concern.

## DNS

- **Root:** `home.arpa` (RFC 8375). No `.lan`/`.local`/`.home`.
- **Zones:** `<plane>.home.arpa` — `clients`, `svc`, `mgmt`, `dmz`, `iot`,
  `lab`, `corp`, `obs`. The overlay is a separate `mesh` namespace.
- **Site-local resolution for replicas:** the same FQDN resolves to the
  nearest instance per site (`s-nebula-container.dmz.home.arpa` → local IP).
- **Distinct instances get distinct names** (`s-nebula-container`,
  `s-nebula-container-b`), never a site suffix.
- **Search domain is policy-derived:** DHCP option 15 = the resolver's
  `allowedNamespaces` from `localDnsSharingIntent`. A mgmt resolver advertises
  `mgmt.home.arpa`; a resolver allowed both `mgmt` and `clients` advertises
  both.
- **Recursion is policy:** `recursiveDnsIntent` relations
  (`allow-<requester>-to-core-dns`, `allow-core-dns-to-wan|overlay`) decide who
  may recurse. The policy node emits the firewall rules; the resolver's
  forwarding config follows from those relations.
- **No zone transfers:** predetermined stub/forward links, derived from the
  relations.

## Reservations (who vs where)

- **Handle** = per-device secret filename `secrets/devices/<handle>.age`
  (`{ "mac": … }`), stable and zone-agnostic.
- **Scope** = public assignment (`<handle> → { scopes.<zone> = <offset> }`),
  reassignable when a device moves planes/sites.

Implemented in `neon-reservations.nix` and `cobalt-reservations.nix`; the
assignment files are public, the `.age` payloads stay encrypted.

## `vlan2` migration (legacy holding pen)

Split `192.168.1.0/24` (neon) / `10.2.2.0/24` (cobalt) into:

- **`mgmt.home.arpa`** — the iDRACs (`s-sigma-idrac`, `s-tau-idrac`,
  `idrac-20x`) and switch admin.
- **`svc.home.arpa`** — servers (`s-sigma`, `s-tau`, `pve-*`, `qnap-*`),
  routers (`s-router-*`).
- **`clients.home.arpa`** — clients (`l-*`, `win-pc-*`).
- **`iot.home.arpa`** — unifi APs, inverters, netgear, printers, `cs-*`.

The per-device handles are already zone-agnostic; a migration only moves the
`scopes` entries to the new zone/VLAN. Handles must never change.

## References

- RFC 8375 — Special-Use Domain `home.arpa.`
- RFC 1034/1035 — DNS hierarchy (subdomain structure)
- RFC 7788 / RFC 7368 — homenet architecture (context)
- Original VLAN-number scheme: `s-router-policy-only/ROUTING-POLICY.md`
  (deleted; superseded by this file).
- Original multi-site overlay plan: `s-router-test/MULTI_SITE_OVERLAY_PLAN.md`
  (deleted; its global-overlay / per-node split is preserved in the `mesh`
  namespace above).
