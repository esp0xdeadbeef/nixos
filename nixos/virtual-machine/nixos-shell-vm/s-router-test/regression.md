# `s-router-test` Security Regression Log

Verified on 2026-04-24. Treat older conclusions as stale.

## Fixed And Live-Verified

- Returned live host after the latest BGP rebuild is:
  - `/nix/store/m070dyjjvlxmnbih6z1386yc42l5sbbp-nixos-system-s-router-test-25.11.20260421.10e7ad5`
- `s88-network-validation-status` is ready on that returned host.
- The root-file refactor is live-validated:
  - the active generation booted successfully after moving the full active model into root `intent.nix` and `inventory.nix`
  - the compatibility wrappers still resolve correctly for BGP and static selection
- `site-c` access-router DNS is fixed live:
  - `c-router-access-mgmt` answers `test-machine-01.printer` and `home-user-01.home-users` locally
  - `c-router-access-media` now answers `test-machine-01.printer`, `home-user-01.home-users`, and public names locally without the earlier `SERVFAIL`
  - `c-router-access-printer` now answers `home-user-01.home-users` and public names locally without the earlier `SERVFAIL`
- `site-c` endpoint name resolution now works live in the intended directions:
  - `sigma-site-c` resolves `test-machine-01.printer` to `10.90.30.2` and `fd42:dead:cafe:30::10`
  - `home-user-01` resolves `test-machine-01.printer` to `10.90.30.2` and `fd42:dead:cafe:30::10`
  - `test-machine-01` resolves `home-user-01.home-users` to `10.90.20.10` and `fd42:dead:cafe:20::10`
- `site-c` endpoint reachability is fixed live for the DNS-backed paths:
  - `sigma-site-c` reaches `test-machine-01.printer`
  - `home-user-01` reaches `test-machine-01.printer`
  - `test-machine-01` reaches `home-user-01.home-users`
- `site-c` recursive DNS works live from the intended endpoints:
  - `sigma-site-c`, `home-user-01`, and `test-machine-01` all resolve `example.com`
- `site-c` direct public DNS leak prevention is fixed live for the verified endpoint contexts:
  - `sigma-site-c` direct `@1.1.1.1` and `@2606:4700:4700::1111` queries time out
  - `home-user-01` direct `@1.1.1.1` queries time out
- `site-c` printer internet egress is blocked live:
  - `test-machine-01` resolves normally but `curl -4 ifconfig.me` and `curl -6 ifconfig.me` time out
- The generalized Nebula bootstrap now runs successfully on the returned host:
  - `nebula-profile-bootstrap.service` finished successfully on the current generation
  - the current journal shows:
    - `Created symlink /etc/systemd/system/multi-user.target.wants/nebula-s-router-test-lighthouse-site-c-storage.service`
- Hetzner now has both modeled lighthouse runtimes live:
  - UDP `4242` is listening for `nebula-s-router-test-lighthouse-east-west.service`
  - UDP `4243` is listening for `nebula-s-router-test-lighthouse-site-c-storage.service`
  - Hetzner now has both overlay interfaces:
    - `nebula0` `100.96.10.254/24` `fd42:dead:beef:ee::254/64`
    - `nebula1` `100.96.20.254/24` `fd42:dead:beef:ec::254/64`
- `site-c` storage-side Nebula containers now boot and hold live runtime state:
  - `nas-node01` `nebula-runtime.service` is active
  - `printer-node01` `nebula-runtime.service` is active
  - `nas-node01` has `nebula1` on `100.96.20.10/24` and `fd42:dead:beef:ec::10/64`
  - `printer-node01` has `nebula1` on `100.96.20.20/24` and `fd42:dead:beef:ec::20/64`
- Previously verified hostile/branch/site-a live properties still check out directly on the current host:
  - `b-router-access-branch` resolves `example.com`
  - `branch-node01` resolves `example.com` and direct `@1.1.1.1` still times out
  - `b-router-access-hostile` resolves `example.com`
  - `hostile-node01` resolves `example.com`, still exits as `46.224.173.254`, and direct `@1.1.1.1` still times out

## Fixed But Only Locally Tested

- `network-control-plane-model` now filters self-listen addresses out of policy-derived DNS forwarders, avoiding self-forward loops; `tests/test-policy-derived-dns-upstreams.sh` passes locally.
- `network-control-plane-model` now preserves authoritative `services.dns.localZones` and `services.dns.localRecords` in runtime-target DNS data; `tests/test-dns-local-records.sh` passes locally.
- `network-renderer-nixos` now renders those authoritative DNS local zones/records into valid quoted unbound `local-data` entries; `tests/test-dns-local-records.sh` passes locally.
- `network-control-plane-model` now preserves modeled `services.mdns` reflector settings in runtime-target service data; `tests/test-mdns-service.sh` passes locally.
- `network-renderer-nixos` now renders modeled `services.mdns` into avahi reflector configuration; `tests/test-mdns-service.sh` passes locally.
- The shared `site-c` profile now injects the same authoritative local zones/records into the media, printer, and NAS edge DNS services instead of only `c-router-access-mgmt`.
- `network-renderer-nixos` now emits a normalized Nebula runtime plan, and `s-router-test` consumes that plan instead of rebuilding overlay runtime state from ad hoc local glue.
- The `site-c` locked-chain local build gate passes in both wrappers:
  - BGP wrapper built `/nix/store/7nr4n5jln5x6qc47pp02f11cra6l8vfb-nixos-system-s-router-test-25.11.20260421.10e7ad5`
  - static wrapper built `/nix/store/vi8f8cj465lcaqj2bjc4fv6zy05pgri7-nixos-system-s-router-test-25.11.20260421.10e7ad5`

## Implemented But Not Yet Live-Validated

- The `site-c` static wrapper is only build-gated locally in the current cycle; I did not yet complete a separate static live reboot/validation pass for the new `site-c` work.

## Still Broken

- `site-c` mDNS discovery is still broken live:
  - `home-user-01` cannot resolve or browse `streaming-cast-01.local`
  - `home-user-01` has mDNS enabled on `eth0` and uses `10.90.20.1` / `fd42:dead:cafe:20::1` as DNS, so this is not just a client resolver being fully disabled
  - `streaming-cast-01` is advertising `_googlecast._tcp` and `_workstation._tcp` locally on its `streaming` segment
  - `streaming-cast-01` still does not show successful reverse discovery of `home-user-01.local`
  - `c-router-access-media` has `avahi-daemon` active and the live shortened interfaces are:
    - `tenant-streami`
    - `tenant-users`
  - discovery still does not cross the media router
  - the current rendered Avahi config still needs to be inspected more directly because the live `/etc/avahi` dump did not yet show an obvious reflector stanza
- `site-c` storage-overlay Nebula is still broken live:
  - `nas-node01` and `printer-node01` now target the correct Hetzner storage endpoint:
    - `46.224.173.254:4243`
    - `[2a01:4f8:c013:628b::1]:4243`
  - both repeatedly send stage-1 handshakes to those endpoints and still time out
  - `nas-node01` live logs show an initial burst of `sendto: network is unreachable`, then repeated `Handshake message sent` followed by `Handshake timed out`
  - direct overlay pings from `nas-node01` and `printer-node01` to `100.96.20.254` and `fd42:dead:beef:ec::254` still fail
  - `nas-node01` underlay route to the Hetzner endpoint is still plain site-c WAN egress:
    - IPv4: `46.224.173.254 via 10.90.40.1 dev eth0`
    - IPv6: `2a01:4f8:c013:628b::1 via fe80::... dev eth0`
  - live policy routing is still wrong for the storage path on `c-router-policy`:
    - `ip -6 route get 2a01:4f8:c013:628b::1 iif downstream-nas` selects `up-iot-wan`
    - `ip -6 route get 2a01:4f8:c013:628b::1 iif down-printer` selects `up-iot-wan`
  - this confirms the current `site-c-storage` path is still modeled as the wrong class of external path for the user’s intended design
- `site-c` is not production-ready yet because the required live discovery and storage-overlay checks still fail.

## Pending Or Unknown

- `!! priority !!` Nebula CA handling is still wrong for the real target model:
  - CA material is still generated and stored directly on disk by the current lab bootstrap
  - there is not yet an encrypted-at-rest CA artifact with password-gated manual retrieval or unseal
  - there is not yet a clean operator-driven flow where a physical or SSH session is required before CA retrieval or cert issuance
  - the intended split is:
    - renderer/control-plane emits desired overlay runtime state
    - the lab may temporarily automate issuance because this is a test VM
    - the real design must require explicit manual unlock and retrieval of the CA
- The rebuild loop still does not complete a trustworthy dry-run/live hash comparison:
  - on the last two returned generations it logged:
    - `expected system evaluation failed; continuing without hash comparison`
    - `error: interrupted by the user`
- `site-c` NAS overlay reachability to the intended storage peers is not yet proven because the storage overlay itself is still failing to establish.

## Next Concrete Debugging Target

- Fix the `site-c` mDNS reflector path in the correct renderer/control-plane layer:
  - inspect the actual rendered avahi configuration on `c-router-access-media`
  - verify whether `services.mdns.allowInterfaces` is still using pre-shortening names while the live interfaces are shortened (`tenant-users`, `tenant-streami`)
  - then revalidate `home-user-01` discovery of `streaming-cast-01`
- Fix the `site-c-storage` Hetzner Nebula path:
  - the host bootstrap is now provisioning the `site-c-storage` remote runtime correctly, but the live route selection is still wrong before the handshake can ever be trusted
  - remodel `site-c-storage` as the user-requested separate-site/upstream shape instead of the current same-site external that falls back to WAN policy
  - then revalidate `nas-node01` / `printer-node01` overlay reachability and no-internet behavior
- After those two fixes, rerun:
  - the local build gate
  - the rebuild loop
  - host validation snapshot wait
  - `site-c` endpoint DNS/leak checks
  - `site-c` mDNS discovery
  - `site-c` printer/NAS Nebula reachability

## Assumptions In The Wrong Layer

- The `site-c` discovery and storage-overlay failures are not `s-router-test`-only problems. If interface-name shortening or Hetzner profile provisioning is wrong, the fix belongs in the renderer/bootstrap chain, not in per-lab shell hacks.
