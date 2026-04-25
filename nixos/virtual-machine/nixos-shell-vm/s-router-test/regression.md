# `s-router-test` Security Regression Log

Verified on 2026-04-25. Treat older conclusions as stale.

## Fixed And Live-Verified

- Current returned host:
  - `/nix/store/2rvs4qjfk25fsms8adn40v1whj1y3jl5-nixos-system-s-router-test-25.11.20260421.10e7ad5`
- `s88-network-validation-status` is ready on that generation.
- `s-router-test` now consumes the canonical locked `network-labs` examples
  directly from [default.nix](/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/default.nix:1):
  - intent:
    `inputs.network-labs/examples/tri-site-dual-wan-overlay-integration-bgp/intent.nix`
  - inventory:
    `inputs.network-labs/examples/tri-site-dual-wan-overlay-integration-static/inventory-base.nix`
- Old local profile wrappers and copied model files have been removed from
  `s-router-test`; the canonical model now lives only in `network-labs`.
- Ownership is now explicit:
  - `network-*` repositories must emit the schemas/runtime plans
  - `s-router-test` must only consume those emitted results and materialize
    disposable emulated nodes around them
- The canonical `network-labs` examples compile in both consumers:
  - BGP:
    - `inventory-nixos.nix` compiles through `network-renderer-nixos`
    - `inventory-clab.nix` compiles through `network-renderer-containerlab-linux-backend`
  - static:
    - `inventory-nixos.nix` compiles through `network-renderer-nixos`
    - `inventory-clab.nix` compiles through `network-renderer-containerlab-linux-backend`
- Disposable Hetzner validator current live state:
  - `eth0` has `2a01:4f8:c013:628b::1/64`
  - `eth0` also has `2a01:4f8:1c17:b337::1/128`
  - the hostile delegated prefix is routed back over Nebula:
    - `2a01:4f8:1c17:b337::/64 via fd42:dead:beef:ee::30 dev nebula0`
  - IPv6 NAT66 is not present on the VPS anymore
- Hostile lane basics on the returned `s-router-test` host:
  - `hostile-node01` has SLAAC GUA addresses from `2a01:4f8:1c17:b337::/64`
  - hostile DNS works through `10.70.10.1`
  - the hostile access router still resolves normally too
  - `b-router-access-hostile` itself does not carry hostile GUA on the
    infrastructure hops:
    - `tenant-hostile` stays `fd42:dead:feed:70::1/64`
    - `transit` stays `fd42:dead:feed:1000::2/127`
- Operator helpers now exist for repeatable validation:
  - [exec-on-remote.sh](/home/deadbeef/github/scripts/exec-on-remote.sh:1)
  - [exec-in-s-router-test-machine.sh](/home/deadbeef/github/scripts/exec-in-s-router-test-machine.sh:1)

## Fixed But Only Locally Tested

- No additional local-only fix is being carried forward in this cleanup round.

## Implemented But Not Yet Live-Validated

- No new implementation is being carried forward here without live proof.

## Still Broken

- `s-router-test` is still not production-ready.
- Hostile public IPv6 egress is still broken on the current returned host even
  though the routed hostile `/64` exists end to end:
  - `hostile-node01` `curl -6 https://ifconfig.me/ip` times out
  - live route selection inside `hostile-node01` still chooses the client-local
    overlay path:
    - `ip -6 route get 2606:4700:4700::1111`
    - `via fd42:dead:beef:ee::254 dev nebula1 table 100 src fd42:dead:beef:ee::30`
  - so the returned host is still using the ULA overlay exit table for public
    IPv6 instead of the routed hostile GUA path
  - the local `hostile-overlay-ipv6-source-fix.service` is failing on boot, so
    the local lab glue is not even applying its own intended source rewrite
  - even after a manual `ip -6 route replace ... src 2a01:4f8:1c17:b337:...`
    in `table 100`, `curl -6` still times out
  - VPS packet capture proves the delegated-GUA path is alive as far as the
    disposable exit:
    - SYN leaves on `eth0` with source `2a01:4f8:1c17:b337:ac54:7ff:fe09:3b24`
    - SYN-ACK returns on `eth0`
    - VPS sends that SYN-ACK back into `nebula0`
  - `hostile-node01` `tcpdump -ni nebula1` sees only outbound SYN packets, not
    the returning SYN-ACK
  - hostile Nebula runtime reports the east-west tunnel as `state: dead`
- Hostile GAU mode must not use NAT66:
  - hostile clients should exit with routed GUA from `2a01:4f8:1c17:b337::/64`
  - routers and intermediate hops must not get those client GUAs
  - NAT66 is explicitly not the intended final design for hostile IPv6
- The router-owned hostile public-exit design is still not represented honestly
  in the active chain:
  - local lab glue still owns part of the hostile exit behavior
  - `b-router-core` still only has interface-based rules:
    - `iif overlay-west -> table 2000`
    - `iif upstream -> table 2001`
  - it does not yet have hostile-source-aware public-default steering that
    would let the modeled core own the public east-west exit cleanly

## Pending Or Unknown

- I have not rerun a full rebuild-loop cycle after this cleanup patch set yet.
- I have not re-verified whether hostile IPv4 stayed green after this cleanup
  round, because the current blocker is specifically hostile IPv6 route
  selection on the live returned host.

## Wrong-Layer Assumptions

- [modules/site-c-storage-route-overrides.nix](/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/modules/site-c-storage-route-overrides.nix:1)
  still injects `ip rule` / `ip route` behavior locally for `c-router-policy`.
  That belongs upstream in the `network-*` model/render chain.
- [modules/overlay-containers.nix](/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/modules/overlay-containers.nix:1)
  still carries hostile-specific overlay exit exceptions and table-100 route
  policy. Those semantics should be modeled upstream, not hand-carried by the
  lab.
- [modules/overlay-containers.nix](/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/modules/overlay-containers.nix:1)
  also owns the failing `hostile-overlay-ipv6-source-fix.service`, which is a
  local attempt to repair hostile GUA source selection after boot. That is
  another concrete example of route/runtime semantics being repaired in the lab
  instead of emitted correctly from the `network-*` chain.
- [modules/nebula-bootstrap.nix](/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/modules/nebula-bootstrap.nix:1)
  and [modules/overlay-containers.nix](/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/modules/overlay-containers.nix:1)
  still materialize Nebula runtime ownership locally. The target is
  renderer-owned runtime consumption from upstream overlay data.
- Delegated-prefix flags and hostile `/64` route semantics should be calculated
  in the model/render chain, not recomputed in the live environment.

## Next Concrete Debugging Target

- Fix hostile IPv6 route selection on the returned host so public IPv6 uses the
  routed `2a01:4f8:1c17:b337::/64` path instead of `nebula1 table 100` with the
  ULA source.
- Then stop trying to rescue that path with more local glue and move the public
  exit to an honest upstream-owned design:
  - renderer/control-plane-owned runtime semantics
  - router-owned terminate-on path
  - no local post-boot repair services for hostile GUA routing
