# Routing policy — cobalt / neon

Multi-site routing and segmentation design. It supersedes the original
`s-router-policy-only/ROUTING-POLICY.md` (VLAN-number scheme) with a
name-based model: the plane is encoded in the DNS suffix, never in the VLAN
number. Sites share one namespace; the site is a routing property, not part
of any name.

## Principles

1. **Plane = name.** The security boundary is expressed as a DNS zone
   (`mgmt.lan`, `dmz.lan`, …), not as a VLAN number. VLAN numbers are
   site-local implementation detail.
2. **One shared namespace.** `lan` / `mgmt.lan` / `dmz.lan` / `iot.lan` are
   global; hostnames are globally unique. No site suffix (`cobalt`/`neon`
   never appears in an FQDN).
3. **Reserve, instantiate lazily.** The full plane taxonomy is reserved here
   (names + spare VLAN ranges). A plane becomes a real VLAN + zone + policy
   relations only when the first device lands in it.
4. **`vlan2` is legacy.** It is a holding pen: split it, do not grow it.
5. **Policy decides recursion.** DNS recursion permission is a
   `recursiveDnsIntent` relation enforced by the policy node. The overlay is
   transport only, never a recursion authority.
6. **No zone transfers.** Topology is intent-driven and static; DNS links are
   predetermined (stub/forward zones) and derived from the policy relations.

## Plane taxonomy

VLAN ranges are *reserved*, not modeled. A range is instantiated only when a
device actually needs it.

| plane        | DNS zone      | trust        | reserved VLAN | status                          |
| ------------ | ------------- | ------------ | ------------- | ------------------------------- |
| control      | `mgmt.lan`    | absolute     | 10–19         | reserved — split out of `vlan2` |
| service      | `lan`         | limited      | 20–29         | live (merged into `lan`)        |
| endpoint     | `lan`         | untrusted    | 30–39         | live                            |
| corp         | —             | semi-hostile | 40–49         | reserved                        |
| iot          | `iot.lan`     | hostile      | 50–59         | live (`vlan7`/`vlan8`)          |
| dmz          | `dmz.lan`     | exposed      | 60–69         | live (`vlan3`)                  |
| lab          | `lab.lan`     | hostile      | 70–79         | reserved                        |
| observability| —             | limited      | 80–89         | reserved                        |
| transit      | `mesh`        | neutral      | 100–199       | live (overlay)                  |
| wan          | —             | unknown      | 1000+         | live                            |

### Trust anchors (normative)

- Control plane is authority. If it grants trust, it lives in `mgmt.lan`.
- Service plane consumes trust; it does not define it.
- Endpoints never reach control directly (bastion/jump only).
- IoT reaches only WAN plus explicitly pinned services.
- DMZ reaches inward only through explicit backends.
- Lab is assumed compromised by design.
- Transit carries routers only: no RA/DHCP/mDNS, `/31` IPv4, `/127` IPv6.

## DNS

- **Shared namespace:** `.lan`, with functional zones `lan`, `mgmt.lan`,
  `dmz.lan`, `iot.lan`. Overlay namespace reserved as `mesh` (separate view).
- **Site-local resolution for replicas:** the same FQDN resolves to the
  nearest instance per site (`s-nebula-container.dmz.lan` → local IP).
- **Distinct instances get distinct names** (`s-nebula-container`,
  `s-nebula-container-b`), never a site suffix.
- **Overlay resolution:** predetermined stub/forward links for `mesh` toward
  the overlay resolver. No zone transfers; the topology is static.
- **Recursion is policy:** `recursiveDnsIntent` relations
  (`allow-<requester>-to-core-dns`, `allow-core-dns-to-wan|overlay`) decide who
  may recurse. The policy node emits the firewall rules; the resolver's
  forwarding config follows from those relations.

## Reservations (who vs where)

- **Handle** = per-device secret filename `secrets/devices/<handle>.age`
  (`{ "mac": … }`), stable and zone-agnostic.
- **Scope** = public assignment (`<handle> → { scopes.<zone> = <offset> }`),
  reassignable when a device moves planes/sites.

Implemented in `site-a-reservations.nix` and `cobalt-reservations.nix`; the
assignment files are public, the `.age` payloads stay encrypted.

## `vlan2` migration (legacy holding pen)

Split `192.168.1.0/24` (site-a) / `10.2.2.0/24` (cobalt) into:

- **`mgmt.lan`** — the iDRACs (`s-sigma-idrac`, `s-tau-idrac`, `idrac-20x`) and
  switch admin.
- **`lan`** — servers (`s-sigma`, `s-tau`, `pve-*`, `qnap-*`), routers
  (`s-router-*`), clients (`l-*`, `win-pc-*`).
- **`iot.lan`** — unifi APs, inverters, netgear, printers, `cs-*`.

The per-device handles are already zone-agnostic; a migration only moves the
`scopes` entries to the new zone/VLAN. Handles must never change.

## References

- Original VLAN-number scheme: `s-router-policy-only/ROUTING-POLICY.md`
  (deleted; superseded by this file).
- Original multi-site overlay plan: `s-router-test/MULTI_SITE_OVERLAY_PLAN.md`
  (deleted; its global-overlay / per-node split is preserved in the `mesh`
  namespace above).
