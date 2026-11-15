# prod-network

Sites are named after chemical elements (e.g. `cobalt`).

The existing `site-a` is grandfathered in under its current name.

## Model trees

Three self-contained model trees live here. They are independent baselines, not
forks of each other: a change in one does not propagate, and each is compiled
against its own inventory and lock pins. The directory names describe the tree,
not the host that consumes it, so read the consumer column rather than guessing
from the name.

| Tree | Host that consumes it | Lock pins |
|---|---|---|
| `prod` | `s-router-cobalt-prod`, `s-router-neon-prod` | `-prod` pinned `network-*` inputs |
| `testing` | `s-router-cobalt-new`, `s-router-neon-new` | `main` pins |
| `current` | `s-router-legacy-prod` | `-legacy-prod` pins |

`testing` is the tree behind the `-new` routers: it is where the current
generation is developed and rolled back to. `current` is the legacy baseline and
is no longer the reference shape.

## Shared source names

Every tree carries the same file names — `intent.nix`, `intent-neon.nix`,
`intent-cobalt.nix`, `inventory-neon.nix`, `inventory-cobalt.nix`,
`runtime-secrets.nix`, `dns-runtime-addresses*.nix` — so a host profile resolves
its model the same way regardless of which tree it selects. The per-site
`intent-<site>.nix` files are thin selectors over `intent.nix`, not copies.

## Removing `current`

`current` is still consumed, so deleting the directory alone breaks evaluation.
Its consumers are:

- `nixos/virtual-machine/nixos-shell-vm/s-router-legacy-prod/default.nix` — the
  whole host, via `modelSource`, `secrets/devices`, and `runtime-secrets.nix`.
- `nixos/server/nixos-shell-vm-inventory.nix` — imports
  `current/inventory-neon.nix` for the `s-router-prod` host and reads one vlan3
  local DNS record (`esp0xdeadbeef-neon-access-vlan3`) to derive a name and an
  IPv4 address.
- `nixos/server/s-nodus/vm-host.nix` — a comment reference only.

Removing it means deleting the `s-router-legacy-prod` host and replacing that one
derived DNS record with an explicit value or with a record read from the tree that
replaces it. Both have to land in the same change; a directory delete on its own
leaves a broken import rather than a failing check.

## Testing

- [`testing/README-tcg-boot.md`](./testing/README-tcg-boot.md) — booting an
  aarch64 router VM on an x86_64 host under QEMU TCG, with no root, no binfmt
  and no access to s-nodus. Covers what that does and does not prove, plus the
  managed-instance path on the board for real forwarding/egress behaviour.
