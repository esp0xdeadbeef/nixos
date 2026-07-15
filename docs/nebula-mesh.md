# Nebula mesh

The lighthouse runs in `s-nebula-container` on `192.168.3.10:4242` and uses
Nebula address `100.64.0.1`. External clients can reach it through the public
ingress endpoint stored in the `nebula-lighthouse-public-ip` SOPS secret; LAN
clients may use the private address directly.

The public ingress path source-NATs traffic to preserve the DMZ return path.
That hides an external client's routable endpoint from the lighthouse, so the
lighthouse also acts as the relay at `100.64.0.1`. Clients advertise that relay
and use it only when they cannot establish a direct peer tunnel.

## Temporary firewall policy

During client onboarding, the Nebula firewall on both the lighthouse and the
shared client profile permits all authenticated overlay traffic in both
directions (`host: any`, `port: any`, `proto: any`). This is the Nebula
certificate-aware firewall, not the NixOS/nftables host firewall. Replace this
temporary policy with scoped rules after the required client flows are known.

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
| `100.64.0.16` | `s-sigma` | allocated |

Do not create a certificate for `s-nebula` itself until it has been assigned a
different, confirmed-free address. The accidentally generated `.12`
certificate was removed without being deployed.
