# `s-router-test` Profiles

Each profile directory contains a matched trio:

- `intent.nix`
- `bgp-inventory.nix`
- `static-inventory.nix`

Current profile families:

- `single-wan`
  Minimal single-site, single-uplink lab.
- `dual-wan`
  Single-site, dual-uplink lab.
- `dual-wan-branch`
  Dual-uplink lab with a second branch site for overlay testing.

Root wrapper files in the parent directory select the active profile:

- `intent.nix`
- `bgp-inventory.nix`
- `static-inventory.nix`
- `inventory.nix`

Compatibility wrappers such as `single-intent.nix` and `multi-bgp-inventory.nix`
remain in the parent directory so older references do not break while the new
profile layout is in use.
