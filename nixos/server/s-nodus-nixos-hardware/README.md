# s-nodus-nixos-hardware (test copy)

This is a **build/compare copy** of `nixos/server/s-nodus` that takes its board
support from the `esp0xdeadbeef/nixos-hardware` fork module
`bananapi/bpi-r4-pro` instead of the host-local board files
(`boot.nix`/`kernel.nix`/`dtb.nix`).

It exists so the nixos-hardware port can be validated against the real host
**without changing `s-nodus` and without risking the board**. Nothing here is
deployed; it is exercised with `nix build`/`nix eval` only.

## What differs from s-nodus

| Concern | s-nodus | this copy |
| --- | --- | --- |
| Kernel | `./kernel.nix` (6.18 + OpenWrt MT7988 delta) | nixos-hardware `bananapi/bpi-r4-pro/linux.nix` (same patch set) |
| Device tree | `./dtb.nix` + `./dtb/*.dts` | nixos-hardware `dtb/` (same resolved DTS) |
| Console / bootargs / no-NixOS-bootloader guard | `./boot.nix` | nixos-hardware `default.nix` |
| FIT + U-Boot env | `./fit.nix` | nixos-hardware `fit.nix` / `uboot-env.nix` |
| `local.bpiR4Pro.enable` | board config owner | thin bridge in `./boot.nix` -> `hardware.bananapi.bpi-r4-pro.enable` |

Everything else (`network.nix`, `cobalt-bridges.nix`, `wifi-ap.nix`,
`vm-host.nix`, `tang.nix`, `disko.nix`, ...) is **imported** from
`../s-nodus/`, not copied: each same-named file here is a three-line
`imports = [ ../s-nodus/<file>.nix ]` re-export. Only the board axis is local:
`default.nix` (which board inputs are wired) and `boot.nix` (the
`local.bpiR4Pro` -> `hardware.bananapi.bpi-r4-pro` bridge).

This is deliberate. The copy used to duplicate every file, and the duplicates
drifted: `internet-guard.nix` here still carried the *old* `/persist`-based
outage counter that the canonical file fixed on 2026-11-10 because it caused a
self-sustaining reboot loop, and `wifi-ap.nix` had drifted apart from the
trunk-bridge fix. Sharing the source makes that class of divergence impossible
and keeps the comparison honest -- the only thing that can differ between the
two hosts is the board support, which is the entire point of the copy.

`networking.hostName` is forced to `s-nodus` so the build is identity-equivalent
(the nebula cert is issued for s-nodus / overlay 100.64.0.18 and the secrets are
keyed under `secrets/s-nodus.yaml`).

## Equivalence checks

- `hardware.deviceTree.dtbSource` is the **same** derivation as s-nodus.
- `boot.kernelPackages.kernel.drvPath` is the **same** derivation as s-nodus.
- The built FIT `system.build.bpiR4ProFit` has byte-identical kernel + all three
  DTBs; only the embedded initrd differs (different eval/system label), which is
  expected and not a hardware difference.

## Using it

```sh
# evaluate / build without deploying
nix eval  .#nixosConfigurations.s-nodus-nixos-hardware.config.networking.hostName
nix build .#nixosConfigurations.s-nodus-nixos-hardware.config.system.build.bpiR4ProFit
```

The `mk-sd-image.sh` here targets `nixosConfigurations.s-nodus-nixos-hardware`
(this copy's configuration), so it can produce a card for on-board testing
without touching the real host's generation.
