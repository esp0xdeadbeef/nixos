# network-* validation: current state and blockers

## Green

network-compiler, network-forwarding-model, network-labs,
network-realization-model, network-realization-schema, network-renderer-nebula,
network-renderer-wireguard, network-renderer-access-endpoint-nixos and
network-renderer-containerlab-linux-backend: latest CI run success.
nixos: `nix flake check --no-build` passes; the dispatched "Flake.lock: update
and push" run and the "Network model check" push run both succeed.

## Fixed in this work

FS-540 named-core DNS endpoints, requester-lane resolver reachability,
policy-lane and ingress policy-table defaults, overlay endpoint host identities
and overlay DNS ingress transit (control plane); tenant-set default attribution
(forwarding model); canonical route-table mapping (renderer); removal of the
obsolete nixos-network-compiler input and of brave in nixos; wrapped-CPM schema
validation (network-realization-schema 30e7372).

## Blocked

- network-control-plane-model: 13 pre-existing module/example migrations
  (FS-260-015, FS-310-120, FS-380-050, FS-410-030, FS-420-030, FS-460-050,
  FS-720-030, FS-740-010, FS-770-010, FS-800-010/012/030, FS-970-040) change
  modeled behavior or acceptance in specific FS areas; AGENTS requires the FS
  contract to move first and this engagement must not touch the URS/FS.
- network-renderer-nixos: 3 cases need an authoritative tri-site overlay example
  with a host inventory; the URS assigns intent to the user, and every
  derivation attempt from existing artifacts failed and was reverted.

Both are ownership/permission limits, not effort.

## Live `curl` failure through s-router-cobalt-new (l-esp)

Observed: DNS (`dig`) and ICMP work, `curl`/TLS fail (hang or "unexpected eof").
Diagnosis: size-dependent forwarding failure (MTU blackhole), not permission —
the rendered policy container carries an unsourced accept for client prefixes
(`allow-cobalt-clients-to-wan`), so TCP is permitted.

The cobalt test model terminates provider sessions (onyx/opal) on
`core-vpn-onyx`/`core-vpn-opal` with `overlay-*-mtu = 1320`. The control plane
published clamp authority only inside the core NAT intent (WAN interfaces), so a
container forwarding into a reduced-MTU tunnel had no explicit clamp set; the
renderer's fallback is skipped when a p2p transit exists.

Fixed in `network-control-plane-model` `3f25981`: every target now publishes
`clampMssInterfaces` from its modeled interfaces with `mtu < 1500`
(`core-vpn-onyx -> ["overlay-onyx"]`, `core-vpn-opal -> ["overlay-opal"]`), which
the renderer installs as `tcp flags syn tcp option maxseg size set`. Control
plane suite: 231 PASS / 11 FAIL, no new failures.

Still needs live confirmation on the box (route MTU, `ip link show wan`,
`sysctl net.ipv4.tcp_mtu_probing`, `tcpdump` on the tunnel/wan) to distinguish a
provider-side MTU/PMTUD blackhole from provider filtering; the model-side clamp
gap is fixed.
