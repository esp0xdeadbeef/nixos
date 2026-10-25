# Booting an aarch64 router VM on an x86_64 host (QEMU TCG)

How to see `s-router-cobalt-new` actually boot without root, without binfmt,
and without touching s-nodus or the running cobalt router.

Script: [`boot-cobalt-new-under-tcg.sh`](./boot-cobalt-new-under-tcg.sh)

## The problem it solves

Building `s-router-cobalt-new` on an x86_64 box works fine — the image is
cross-built by the remote aarch64 builders, so nothing heavy runs locally:

```
$ nix build .#nixosConfigurations.s-router-cobalt-new.config.system.build.nixos-shell
/nix/store/...-nixos-vm
```

But *running* it via the generated runner does not:

```
$ .../bin/run-s-router-cobalt-new-vm
.../coreutils-9.11/bin/readlink: cannot execute binary file: Exec format error
```

The runner is an **aarch64** artifact: it execs aarch64 coreutils. On an
x86_64 host that only works when the kernel has aarch64 binfmt emulation
registered, which means

```nix
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
```

— a root-owned, persistent host change. The script deliberately avoids it.

It also does not use `br-cobalt-lan` / `br-cobalt-wan`, which exist only on
s-nodus.

## What it does

It re-implements the runner's QEMU invocation by hand:

1. reads the kernel / initrd / system paths **out of the generated runner**
   rather than guessing store paths,
2. creates a disk image labelled `nixos` (the initrd waits on
   `/dev/disk/by-label/nixos`; without the label the boot drops to emergency
   mode),
3. supplies the three 9p tags the guest mounts — `nix-store`, `shared`,
   `xchg` — plus the `a450e1c198d7832105aba51788209f6` tag for
   `/persist-state`,
4. boots with `qemu-system-aarch64 -accel tcg`.

Missing 9p tags are the second classic failure: the guest reaches
`Reached target Initrd File Systems` and then hangs on
`9pnet_virtio: no channels available for device shared`.

## Usage

```bash
VM=$(nix build --no-link --print-out-paths \
       .#nixosConfigurations.s-router-cobalt-new.config.system.build.nixos-shell)

./prod-network/testing/boot-cobalt-new-under-tcg.sh "$VM" 300
```

Success line is:

```
[ OK ] Reached target Login Prompts.
hostname=s-router-cobalt-new
```

All 15 modelled containers start (`access-*`, `core`, `core-vpn-*`,
`policy`, `upstream-selector`, `downstream-selector`).

Timing on a 24-core x86_64 box, TCG, `-smp 2 -m 1536`: **~270s** to login.
That number is emulation, not hardware — the BPI-R4 runs the same guest under
KVM.

## What it proves, and what it does not

**Proves**

- the kernel, initrd and init boot,
- systemd reaches multi-user with the full container set,
- per-unit start ordering and which units fail,
- boot-time regressions between two revisions (compare like for like).

**Does not prove**

- **forwarding, VLANs, egress, DNS, traceroute, or flap behaviour** — it uses
  `-netdev user`, not the real bridges. Those results only come from
  s-nodus.
- anything about secrets: SOPS material is absent, so
  `Materialize the Nebula PKI profile for core-vpn-garnet-cobalt` fails
  closed. That is the secrets boundary working, not a defect.

## For real behaviour: s-nodus

This script answers "does it boot". It cannot answer "does it route". For
that, use the managed-instance path on the board itself:

```bash
vm-update s-router-cobalt-new /home/deadbeef/github/nixos
systemctl start s-router-cobalt-new-vm.service   # after stopping prod
systemctl stop  s-router-cobalt-new-vm.service
systemctl start s-router-cobalt-prod-vm.service
```

Caveats learned the hard way:

- `vm-update` only accepts **managed** instances. `s-router-cobalt-new` is not
  one on s-nodus today (`vmName = "s-router-cobalt-prod"` in
  `nixos/server/s-nodus/vm-host.nix`), so `vm-update s-router-cobalt-new ...`
  fails with `nixos-shell-vm-manager: unmanaged VM: s-router-cobalt-new`.
- **Do not stop `nixos-shell-wan-router-vms.service`.** It is the recovery
  mechanism. It honours an explicit stop, so a `systemctl stop` of the prod VM
  is *remembered*:

  ```
  s-router-cobalt-prod: carrier-up start preserved explicit-stop authority
  ```

  Which means: if you stop prod and your restore path fails, nothing brings it
  back. Keep the watcher running and restore with
  `systemctl start s-router-cobalt-prod-vm.service`.
- `br-cobalt-lan` / `br-cobalt-wan` are shared with prod. Only one cobalt
  router can run at a time.
