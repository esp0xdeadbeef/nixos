# prod-network

Sites are named after chemical elements (e.g. `cobalt`).

The existing `site-a` is grandfathered in under its current name.

## Testing

- [`testing/README-tcg-boot.md`](./testing/README-tcg-boot.md) — booting an
  aarch64 router VM on an x86_64 host under QEMU TCG, with no root, no binfmt
  and no access to s-nodus. Covers what that does and does not prove, plus the
  managed-instance path on the board for real forwarding/egress behaviour.
