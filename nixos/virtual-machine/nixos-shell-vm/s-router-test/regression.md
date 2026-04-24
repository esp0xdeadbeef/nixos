# `s-router-test` Security Regression Log

Verified on 2026-04-24. Treat older conclusions as stale.

## Fixed And Live-Verified

- Returned live host after the latest BGP rebuild is:
  - `/nix/store/2x40w6r19fg0d6q8i3sbvdb32vy1zacq-nixos-system-s-router-test-25.11.20260421.10e7ad5`
- `s88-network-validation-status` is ready on that returned host.
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
- The `site-c` locked-chain local build gate passes in both wrappers:
  - BGP wrapper built `/nix/store/7nr4n5jln5x6qc47pp02f11cra6l8vfb-nixos-system-s-router-test-25.11.20260421.10e7ad5`
  - static wrapper built `/nix/store/vi8f8cj465lcaqj2bjc4fv6zy05pgri7-nixos-system-s-router-test-25.11.20260421.10e7ad5`

## Implemented But Not Yet Live-Validated

- The `site-c` static wrapper is only build-gated locally in the current cycle; I did not yet complete a separate static live reboot/validation pass for the new `site-c` work.

## Still Broken

- `site-c` mDNS discovery is still broken live:
  - `home-user-01` cannot resolve or browse `streaming-cast-01.local`
  - `streaming-cast-01` cannot resolve or browse `home-user-01.local`
  - `c-router-access-media` has `avahi-daemon` active and an nft `allow-mdns-service` rule, but discovery still does not cross the media router
- `site-c` storage-overlay Nebula is still broken live:
  - `nas-node01` and `printer-node01` have `nebula1` up on `100.96.20.0/24` and `fd42:dead:beef:ec::/64`
  - both repeatedly try to handshake to Hetzner `46.224.173.254:4242` / `[2a01:4f8:c013:628b::1]:4242`
  - those handshakes time out continuously
  - neither node can reach tested overlay peers such as `100.96.10.254`, `fd42:dead:beef:ee::254`, `100.96.10.1`, or `fd42:dead:beef:ee::1`
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
- The current BGP reboot returned a new host generation, but the rebuild loop still did not complete a trustworthy dry-run/live hash comparison:
  - `expected system evaluation failed; continuing without hash comparison`
  - `error: interrupted by the user`
- `s88-network-validation-status` on the returned host reports `dnsA=fail` / `dnsAAAA=fail` for `b-router-access-branch` and `b-router-access-hostile`, but direct live checks after the snapshot show both access resolvers and both endpoints resolving normally again. That mismatch is currently unresolved.
- `site-c` NAS overlay reachability to the intended storage peers is not yet proven because the storage overlay itself is still failing to establish.

## Next Concrete Debugging Target

- Fix the `site-c` mDNS reflector path in the correct renderer/control-plane layer:
  - verify whether `services.mdns.allowInterfaces` is still using pre-shortening names while the live interfaces are shortened (`tenant-users`, `tenant-streami`)
  - then revalidate `home-user-01` discovery of `streaming-cast-01`
- Fix the `site-c-storage` Hetzner Nebula path:
  - verify the Hetzner-side profile/service for the `100.96.20.0/24` / `fd42:dead:beef:ec::/64` overlay
  - verify the host bootstrap is actually provisioning the `site-c-storage` remote runtime, not just the east-west runtime
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
