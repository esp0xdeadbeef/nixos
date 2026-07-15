# Nebula mesh

The lighthouse runs in `s-nebula-container` on `192.168.3.10:4242` and uses
Nebula address `100.64.0.1`. External clients can reach it through the public
ingress address `SOPS-configured-address:4242`; LAN clients may use the private address
directly.

## Address allocations

| Address | Node | Status |
| --- | --- | --- |
| `100.64.0.1` | `beacon` (`s-nebula-container`) | lighthouse |
| `100.64.0.10` | `l-esp` | allocated |
| `100.64.0.11` | `s-test` | allocated |
| `100.64.0.12` | unknown existing node | reserved/in use; do not allocate |
| `100.64.0.13` | `l-envil` | allocated |
| `100.64.0.14` | `l-portal` | allocated |
| `100.64.0.15` | `s-gamma` | allocated |

Do not create a certificate for `s-nebula` itself until it has been assigned a
different, confirmed-free address. The accidentally generated `.12`
certificate was removed without being deployed.
