# NixOS Repo Improvement Plan

This is a planning note only. Do not implement these changes while the current
repository changes are still being validated.

Everything here is **open work**. Completed migrations (the `relativeRepo`
helper, the `cudaCache` module, the nixos-shell VM host profile, the LLM
profiles, removal of `outPath`) have been dropped from this document — do not
re-add them as proposals. If a step below is finished, delete it rather than
leaving it as history.

## Current Structure

The repo originated from Misterio77's `nix-starter-configs` and evolved into an
active personal + production config. That history is useful context, but the
structure should now be treated as a deliberate design, not a starter template.

The flake owns host discovery. `flake.nix` scans these roots and creates every
`nixosConfigurations` entry automatically:

- `nixos/laptop`
- `nixos/server`
- `nixos/virtual-machine/nixos-shell-vm`
- `nixos/virtual-machine/dedicated-vm`
- `nixos/virtual-machine/nixos-anywhere`

There is one arch override (`hostSystems`), for the non-x86 laptop. Do not
replace discovery with a hand-maintained host list.

The broad areas:

- `nixos/`: concrete hosts, hardware, service stacks, VM definitions.
- `home-manager/`: per-user Home Manager configs plus shared snippets.
- `library/`: helpers plus the residual `library/01-general` tree.
- `profiles/`: named NixOS and Home Manager profiles; the main reusable layer.
- `modules/nixos` and `modules/home-manager`: exported module surfaces.
- `overlays/`, `pkgs/`, `secrets/`: overlays, local packages, SOPS data.

## Progress Since The Last Revision

Recorded so the remaining work can be scoped correctly.

- **The `library/01-general` catch-all bundle is no longer imported.** No host
  imports `library/01-general/default.nix`; the file is now dead. Hosts import
  focused `profiles.*` plus a shrinking set of individual paths. The split is
  what remains, not the decision to do it.
- **The named-profile layer exists and is the live path.** `profiles/nixos/`
  now carries `base`, `core`, `boot`, `desktop`, `containers`, `editors`,
  `packages`, `nixpkgs`, `nix`, `network`, `virtualization`, `workstation`,
  `server`, `laptop`, `llm`, `mail`, `web`, `sops`, `users`, `vm-host`, and
  more, all registered in `profiles/default.nix`. The "Proposed Target Layout"
  below is largely the shape that now exists; treat it as ratification, not a
  proposal.
- **`modules/nixos` carries real modules** (`container-network-defaults`,
  `container-profile`, `cuda-cache`, `local-users`), not placeholders.

Two regressions worth naming because they recur: commits that claim to remove a
stale host stub have twice been undone by an unrelated "also add ..." line in a
later mixed commit (`fd716cf5`/`21cb4f96` undone by `4da3a04f`). Both stub
hosts were re-removed in `d87b816c` and `0fa2eb3c`. Keep stub removal commits
single-purpose and check `git log --diff-filter=A` before re-touching them.

## Open Problems

These are the things still worth changing. Each maps to a cleanup step below.

### Imports

- Residual `library/01-general` imports: 39 occurrences across 25 files, hitting
  23 distinct targets. The heavy repeats are `network/ssids.txt` (4),
  `desktop/shell-env.nix` (4), `system/autoupdate.nix` (4),
  `password-cracking/default.nix` (4), `system/garbage-collection.nix` (3),
  `network/wifi-ssid-derive.sh` (3). These are mechanical profile moves plus a
  `network` profile that owns the ssid data files.
- `library/01-general/default.nix` is dead code: nothing imports it, but it
  still imports ~45 modules and reads as the repo's centrepiece. Delete it with
  the last of its split, or it will be re-adopted by mistake.
- Two import philosophies coexist and the live code contradicts the stated
  rule. The README and AGENTS.md say to import by explicit intent, yet
  `library/imports.nix` still provides `enabledImports` /
  `enabledImportsRecursive` directory-scanning discovery, and it is still called
  from `home-manager/l-esp/configs/default.nix` and
  `nixos/laptop/l-esp/optional/default.nix`. Either migrate those two call sites
  to explicit imports and retire the helper, or document the exception. Do not
  leave both conventions undocumented.

### Host naming (routers)

The router VMs are named along two independent axes — **site** and **stability
posture** — but the names encode neither consistently. The sites are
`esp0xdeadbeef.neon` and `esp0xdeadbeef.cobalt` (`prod-network/prod/intent.nix`
lines 174 and 1984). The posture axis is "tracks unpinned `main`" versus "pinned
to the `-prod` network inputs".

| Host | `modelSource` | network-* inputs | Site it renders |
|---|---|---|---|
| `s-router-cobalt-new` | `prod-network/testing` | stable (`network-*`) | cobalt |
| `s-router-cobalt-prod` | `prod-network/prod` | `-prod` pinned | cobalt |
| `s-router-prod` | `prod-network/prod` | `-prod` pinned | **neon** |
| `s-router-neon` | `prod-network/testing` | stable (`network-*`) | neon |
| `s-router-cobalt` | `prod-network/testing` | stable (`network-*`) | cobalt |
| `s-router-legacy-prod` | `prod-network/current` | `-legacy-prod` | neon (frozen) |

The defect is the neon pair. `s-router-prod` is the prod-pinned **neon** router
but carries no site in its name, and `s-router-neon` is the unstable neon router
without the posture suffix. This is not inferred from the directory names: each
host pins its site explicitly via `inventoryFileName`, and
`s-router-prod`, `s-router-neon`, and `s-router-legacy-prod` all select
`inventory-neon.nix`, while the three cobalt hosts select
`inventory-cobalt.nix`. Cobalt got the naming right (`-new` vs `-prod`); neon did
not. Naming should be `<site>-<posture>` throughout:

- `s-router-prod` → `s-router-neon-prod`
- `s-router-neon` → `s-router-neon-new`
- `s-router-cobalt-prod`, `s-router-cobalt-new`: already conformant
- `s-router-cobalt`: overlaps `s-router-cobalt-new` (same lab source, same
  stable inputs); decide whether it is the site's dev box or drop it
- `s-router-legacy-prod` → `s-router-neon-legacy-prod` if kept

Two constraints before acting. First, `productionSelector = hostName` and
`selectorFile` both embed the host name, so a rename touches the host directory,
`hostSystems` entries in `flake.nix`, the `nixos-shell` build mapping, every
`sops` path keyed by host name, and the rendered `networking.hostName` inside
secrets-adjacent files — this is not a `git mv`. Second, `s-router-prod`,
`s-router-legacy-prod`, and everything under `prod-network/{prod,current}/` are
protected: do not start this rename without explicit, per-session permission
naming the exact files.

**Status: recorded, deliberately NOT executed.** `s-router-prod` is the live
router at the neon site. Renaming it is a deploy-time change to a running host,
not a refactor: it renames the machine, rewrites secrets paths, and invalidates
the rendered identity the site currently depends on. **Do not rename
`s-router-prod` while it is the box in service.** Treat this section as the
target scheme to adopt at the next moment the neon router is rebuilt from
scratch (next clean reinstall, or a planned maintenance window with a rollback
path), not as a task on the cleanup list. Step 11 below is gated on that and must
not be scheduled against a live site.

Also note the naming lies about content in one direction: `s-router-cobalt-prod`
renders the `access-*` + `core-vpn-onyx/opal` set while `s-router-cobalt` renders
`core-vpn-garnet-cobalt` as well, so "prod" and "dev" differ in VPN cores, not
just pinning. Settle what each host is *for* before renaming, or the rename just
moves the ambiguity.

### Conventions

- AGENTS.md prescribes top-level modules as `{ pkgs, lib, config, inputs, ... }`
  and feature flags via an `enable` boolean, but only a minority of `.nix` files
  use `mkOption` / `mkEnableOption`, and many `profiles/*` files are bare
  `imports` aggregators with no option. Decide whether the option convention
  applies to new modules only or retroactively, and write that down.

### Tooling

- The formatter gate does not gate. The `formatter` in `flake.nix` runs
  `nixpkgs-fmt .` with no arguments (it *formats*, it does not *check*), and the
  explicit-file path exits 0 with `No .nix files supplied; skipping formatter.`
  when handed no `.nix` file. Nothing enforces the AGENTS.md formatting rule, and
  the tree has drifted. Fix the wrapper, then clear the drift.
- The AGENTS.md checking gate, `nix flake check --all-systems`, has no PR-time
  workflow. CI carries only `flake-lock-update-main.yml` and
  `network-model-check.yml`; neither runs a flake check. A push/PR check would
  close the loop for ordinary changes.

### Repo hygiene

- Stale local refs: seven local branches (`backup-pre-scrub`,
  `backup/pre-push-20260830`, `backup/pre-rebase-20261006-1841`, `merged-main`,
  `s-router-test-prod-safe`, `work-laptop-merge-base`, plus `main`) and **two**
  live stashes: `stash@{0}` `tang-migration-wip` (2026-10-24) and `stash@{1}`
  `WIP intent revert captured before restore` (2026-09-17). `stash@{1}` sits on
  top of protected `prod-network` intent and must be resolved explicitly before
  further network work, not left dangling. There are still no tags, so these
  branches hold the only refs to that history; delete them only after confirming
  nothing unique is lost.
- `overlays/not-workingyet/` (tracked: `flake.nix`, `flake.lock`) is
  unreferenced and overlaps the stale-file cleanup.
- `library/02-window-manager-i3` and `library/03-window-manager-sway` still
  exist and both are still reached, so they cannot simply be deleted: `i3`
  comes from `profiles/nixos/desktop/i3.nix` **and**
  `nixos/virtual-machine/dedicated-vm/l-envil-llm-jail/default.nix`, while
  `sway` comes from `profiles/nixos/desktop/sway.nix`. They now overlap with
  the desktop profiles that wrap them, so the fix is to fold each bundle's
  content into its owning `profiles/nixos/desktop/{i3,sway}.nix`, repoint the
  `l-envil-llm-jail` importer at the profile, and only then delete both
  directories.

### Unstable Package Set (adoption gap)

`pkgs.unstable` exists but is barely adopted: one module uses `pkgs.unstable.*`,
while ad hoc `inputs.nixpkgs-unstable` reaches across `overlays/unstable-packages.nix`,
`home-manager/s-test-vm/home.nix`, and
`library/01-general/packages/pentesting/packages.nix`. Normalize before the
`01-general` split hardens the current access pattern into a profile.

### Memory reclaim policy is absent, and it costs wifi (l-esp case study)

There is **no** `vm.*` sysctl configuration anywhere in the repo (`grep -rn
'"vm\.' --include=*.nix` returns nothing), and swap/zram policy is duplicated
per host with three different values:

| Host | zram | swapfile | `vm.*` tuning |
|---|---|---|---|
| `l-esp` | `memoryPercent = 50` (`hardware/btrfs-scrub.nix`) | 45 GiB (`hardware/suspend-to-disk.nix`) | none |
| `s-nodus` | `memoryPercent = 100` (`default.nix`) | 64 GiB | none |
| `l-envil` / `l-portal` | none | none | none |

`/tmp` is a bare tmpfs on every laptop, inheriting half of RAM with no size cap.

#### Symptom

`l-esp` (30 GiB, i7-12850HX) reported 329 `wlp0s20f3` wifi auth/deauth events and
**313 `page allocation failure`** plus **458 `Tx queue alloc failed`** across one
7.5-day boot. All 35 recorded failures were order-6 (256 KiB contiguous) in
`iwl_pcie_txq_alloc`, driven by `iwl_mvm_add_new_dqa_stream_wk` — i.e. every new
station/stream. When `iwl_mvm` cannot get its TXQ, the STA stream is never set
up, traffic stalls, and the connection tears down. It surfaces as "wifi
flapping" and gets misattributed to router rebuilds.

#### Actual cause (measured, not inferred)

Not memory exhaustion and not an out-of-tree driver:

- `MemAvailable` was 13-16 GiB throughout; PSI memory `full avg300 = 0.01`; no
  OOM kills. `iwlwifi`/`iwlmvm` are **in-tree**
  (`/run/booted-system/kernel-modules/.../iwlwifi.ko.xz`). Kernel taint is
  `4097` = `P|O`, contributed **only** by `nvidia`, `nvidia_drm`,
  `nvidia_modeset`, `nvidia_uvm` — unrelated to wifi.
- It is **fragmentation**. At failure time `Node 0 Normal` had ~1.0 GiB free
  while the buddy allocator showed **zero blocks above order-3**:
  `441073 238919 55988 7580 0 0 0 0 0 0 0`.
- Compaction is not idle — `compact_daemon_wake 516206`, 1.25e9 pages scanned,
  against `compact_success 468` / `compact_fail 1271` and
  `allocstall_movable 1155047`. Forcing `compact_memory` made it *worse*
  (441k → 18k free pages) and still produced no order-4+ block.
- The blocker is **reclaimable slab**. `SReclaimable` was 4.3 GiB (dentry/inode),
  `vfs_cache_pressure` at its default 100. `drop_caches` immediately restored
  order-4/-5/-6 (166 order-6 blocks) — and slab was back at 4.2 GiB within
  seconds, re-fragmenting the zone. Combined with 13.1 GiB of compressed anon
  held in zsmalloc (unmovable, in-zone) and 2.5 GiB of tmpfs `shmem` in `/tmp`,
  the high-order pool never survives long enough for `iwlwifi` to use it.

So the config is "decent" in the sense that nothing is on fire, but it has no
memory-reclaim policy at all, and the default swappiness=60 pushes anon into
zsmalloc instead of reclaiming the slab that actually blocks the allocation.

#### Gaps to fix

1. **No shared memory profile.** Create `profiles/nixos/hardware/memory.nix`
   (and route `intel-workstation`, `l-envil`, `l-portal`, `s-nodus` through it)
   that owns zram, swapfile, tmpfs caps, and the `vm.*` sysctls in one place.
   Three hosts currently pick three different zram values for no documented
   reason.
2. **zram sizing.** `memoryPercent = 50` on a 30 GiB host yields a 15.5 GiB
   device that is currently 79% occupied. Cap zram by *actual* memory used, not
   device size, and drop to ~25% so compressed anon stays a fraction of RAM.
3. **No high-order reserve.** `min_free_kbytes = 67584` is order-0 scaled;
   nothing keeps a contiguous pool available. Raise it and widen the kswapd
   window (`watermark_scale_factor`).
4. **`watermark_boost_factor = 15000` is counterproductive here** — it fires
   (`boost:193272kB` observed) and still cannot satisfy order-6, burning reclaim
   cycles. Set to 0 on hosts running `iwlwifi`.
5. **`swappiness = 60`** lets anon fill zsmalloc while 10.8 GiB of reclaimable
   pagecache sits idle. Lower it.
6. **`vfs_cache_pressure = 100`** does not push dentry/inode slab out under
   this workload; the 4.3 GiB slab is what blocks compaction. Consider raising
   it (and/or bounding slab) so reclaimable slab does not monopolize the zone.
7. **`/tmp` is an uncapped tmpfs** (`fileSystems."/tmp".device = "tmpfs"` in
   three host files, no `size=`). 2.1-2.5 GiB of `shmem` was resident and is
   unmovable. Add a size cap and a `nr_inodes` cap.
8. **`systemd-oomd` is enabled with an empty config** (default
   `oomd.conf` = `[OOM]` only), so its default thresholds can never fire on this
   workload. Either configure thresholds against the measured PSI numbers or
   drop it in favour of a policy that matches the failure mode.
9. **`journalctl --disk-usage` was 3.9 GiB** with `Storage=persistent` and no
   `SystemMaxUse`; combined with unbounded slab this is more reclaimable
   pressure than the high-order pool tolerates.

#### Verification recipe

These are the checks that produced the diagnosis; use them to prove a fix:

```sh
# 1. Is it fragmentation? high-order blocks vs. free pages
tr -s ' ' < /proc/buddyinfo | grep Normal   # zeros above order-3 => fragmented
# 2. Is compaction even trying?
grep -E 'compact_|allocstall' /proc/vmstat  # high daemon_wake + low success
# 3. Is reclaimable slab the blocker?
grep -E 'SReclaimable|SUnreclaim' /proc/meminfo
sync; echo 1 > /proc/sys/vm/drop_caches       # order-6 reappears => slab
# 4. Confirm the consumer is iwlwifi and not a bad driver
dmesg | grep -c 'Tx queue alloc failed'
for m in /sys/module/*; do [ -s $m/taint ] && echo "$m: $(cat $m/taint)"; done
```

Do **not** treat `iwl_pcie_txq_alloc` failures as a hardware/`iwlwifi` bug until
`/proc/buddyinfo` shows order-6 availability. The driver is the victim.

### s-nodus (100.64.0.18): stale build, unpinned TSO guard, oversized zram

Same measurement pass, different host and a different failure profile. Board:
Banana Pi BPI-R4 Pro 4E, MediaTek MT7988A, **4 cores / 3.8 GiB**, kernel 6.18.60,
uptime at capture 25 min, hosting `s-router-cobalt-prod-vm.service` (QEMU,
`-m 2048`, `-smp 4`). The MT7996 wifi is out of scope (not mainline), so the
l-esp `iwlwifi` failure mode cannot occur here.

`vm.*` is **entirely default** here too, identical to l-esp:

```
vm.swappiness = 60          vm.min_free_kbytes = 45056
vm.watermark_boost_factor = 15000   vm.watermark_scale_factor = 10
vm.vfs_cache_pressure = 100 vm.compaction_proactiveness = 20
vm.overcommit_memory = 0    vm.panic_on_oom = 0
```

Unlike l-esp there is **no** fragmentation and no allocation failure
(`page allocation failure` count 0, taint 0, `allocstall_*` all 0, `pgsteal_*`
all 0). The cost here is **CPU**, not memory:

- PSI CPU `some avg300 = 33.24`, `avg60 = 47.33`.
- `vmstat` shows `gu` (guest) at **20-31%** and `sy` at **12-27%** on 4 cores.
- `qemu-system-aa` at ~301% CPU for a 2048 MiB VM, with `CPUAffinity=` empty
  and `Nice=0` — the VM competes with everything else on all 4 cores.

#### Findings

1. **The running system is a month stale and the TSO/GSO guard is not active.**
   `network.nix` defines `systemd.services.mtk-eth-tso-off`, and it is present
   in current flake HEAD:

   ```sh
   nix eval .#nixosConfigurations.s-nodus.config.systemd.services \
     --apply builtins.attrNames | grep mtk   # -> "mtk-eth-tso-off"
   ```

   But on the host that unit **does not exist**:

   ```sh
   systemctl status mtk-eth-tso-off   # Unit mtk-eth-tso-off.service could not be found
   sudo ls /run/current-system/etc/systemd/system/ | grep -i mtk   # (nothing)
   ```

   and the offloads it is supposed to disable are **on** on every port:

   ```
   eth1/eth2/end0: tx-tcp-segmentation: on, generic-segmentation-offload: on
   ```

   Current system: `nixos-system-s-nodus-sd-card-26.05.20261105.c56a87d`
   (generation 72, 2026-11-08 02:02). `network.nix` was written 2026-10-07 in
   `e4156dc6`. So the guard is deployed in git but **not on the board**. This is
   silent drift, not a code bug — and it matters because the comment in
   `network.nix` declares the MT7988 TXD-ring corruption (0x77777777 poison, TX
   timeout) is only *avoided* by this guard. The board is currently running
   without its documented mitigation.

   **The kernel patches 981/982 are themselves correct — verified, not assumed.**
   They apply cleanly to the 6.18.60 source the config actually builds:

   ```sh
   # base is 6.18.60, patches claim a 6.18.55 rebase
   nix eval --raw .#nixosConfigurations.s-nodus.pkgs.linux_6_18.version  # 6.18.60
   patch -p1 --dry-run < .../981-...tx-timeout.patch   # all hunks OK, offset -263
   patch -p1 --dry-run < .../982-...warm-reset-fix.patch # hunk OK, offset -386
   ```

   and both are wired into the build:

   ```sh
   nix eval --json .#nixosConfigurations.s-nodus.config.boot.kernelPackages \
     .kernel.kernelPatches --apply 'ps: map (p: p.name) ps'
   # -> [..., "mtk-eth-tx-timeout-single-dev-recovery", "mtk-eth-warm-reset-poll-fix"]
   ```

   The running module is provably the *unpatched* 6.18.60: decompiling it shows
   the old `"transmit timed out"` and `"warm reset failed"` strings and **not**
   981's `"stalled with no FE error"` or 982's deasserted-poll path. Unpatched
   6.18.60 has those strings at `mtk_eth_soc.c:3366` and `:3995`; the 981 hunks
   land exactly there. So: **patches good, build config good, deployment stale.**
   Nothing to fix in the patch set — only the generation on the board.
2. **zram is sized at 100% of RAM with no cap.** `zram-generator.conf` is
   `zram-size=100 / 100 * ram`, from `zramSwap.memoryPercent = 100` in
   `nixos/server/s-nodus/default.nix`. On a 3.8 GiB board that is a 3.8 GiB
   device. `/sys/block/zram0/mem_limit` is **not exposed** by this kernel build
   (`ENOENT`), so there is no hard ceiling on zsmalloc growth — on a board whose
   entire job is to host a 2 GiB VM, compressed anon competes directly with it.
   Contrast `l-esp` (`memoryPercent = 50`, priority 100): three hosts, three
   different zram policies, none documented.
3. **zram priority 5 is below the swapfile (-2).** Kernel swaps to the
   *higher* priority first, so zram wins here, which is the intent — but the
   pair `(100, prio 5)` and `(50, prio 100)` across two hosts means the
   documented intent differs per host with no written rationale.
4. **Swap is completely unused** (0 B of 67 GiB) while 1.58 GiB `AnonPages`
   sits resident on a 3.8 GiB board. Not wrong today, but it means the zram
   sizing has never been exercised — the first time it is, it will be under VM
   pressure, which is the worst moment to discover the bound is absent.
5. **`systemd-oomd` enabled, config empty** (`/etc/systemd/oomd.conf` =
   `[OOM]` only), same as l-esp. With `ManagedOOMMemoryPressure=auto` and no
   PSI pressure observed, it will never act; if zram does fill, it fires late
   and picks a victim by cgroup rather than by the VM's importance.
6. **No CPU isolation for the router VM.** `CPUAffinity=` empty, `Nice=0`,
   `IOSchedulingClass=2`. A 4-core/4-vCPU VM with no reservation will starve the
   host's own netdev/softirq path under load — which is the one path the board
   exists to serve. This is the actual explanation for `some avg60 = 47%` PSI CPU
   on a machine with no page failures.
7. **Journal is unbounded** (`Storage=persistent`, no `SystemMaxUse`):
   724 MiB here, 3.9 GiB on l-esp. Smaller absolute impact on this board but the
   same missing policy.

#### Gaps to fix

1. **Rebuild and re-activate s-nodus first.** Until generation 72 is replaced,
   everything in `network.nix` is `improvement.md` fiction, not deployed state —
   including the now-fixed TSO guard assertion and the already-correct kernel
   patches 981/982. This is also the cleanest test of whether the `aarch64`
   builder path from l-esp still works (it did during this investigation: the
   unit built on `s-sigma-builder`). Confirm with
   `systemctl status mtk-eth-tso-off` **and**
   `ethtool -k eth1 | grep tcp-segmentation-offload`, plus
   `xzcat .../mtk_eth.ko.xz | strings | grep 'no FE error'` to prove 981 landed.
2. Merge s-nodus into the shared `profiles/nixos/hardware/memory.nix`
   (step 14 above). It is the host most exposed to the zram decision, because
   the VM's working set is a large fraction of RAM.
3. Size zram against RAM *minus* the VM reservation, not total RAM. With a
   fixed 2048 MiB guest, `memoryPercent` should be a small fraction, not 100%.
4. Add CPU allocation for the VM: either pin the vCPUs and leave core 0 for
   host netdev/softirq, or set `Nice`/`CPUWeight` on the VM slice. Measure with
   `vmstat 1` `gu`/`sy` and `/proc/pressure/cpu` before and after.
5. Bind journald like l-esp (`SystemMaxUse`).
6. **Verify the TSO guard actually applies.** — **DONE (code fix applied).**
   `nixos/server/s-nodus/network.nix` now asserts the result instead of ending
   every call in `|| true`. The unit reads back
   `tcp-segmentation-offload` and `generic-segmentation-offload` per interface
   and exits non-zero if either is not `off`, and it `partOf`
   `systemd-networkd.service` so a networkd restart (which is what a netdev
   stop/start does, including patch 981's per-netdev recovery) re-applies it.
   Verified: the readback expression returns `on` against today's host (i.e. it
   would have caught the drift) and `off` immediately after
   `ethtool -K eth1 tso off gso off`. Still outstanding: nothing in CI/SAT
   detects a *missing* unit, only a failing one — a rebuild that drops
   `mtk-eth-tso-off` entirely is still silent. Consider a SAT row for it.

#### Verification recipe (s-nodus)

```sh
# stale-build detection: config in HEAD but not on the host
systemctl status mtk-eth-tso-off --no-pager | head -3
sudo ethtool -k eth1 | grep -E 'tcp-segmentation-offload|generic-segmentation'
# CPU cost of the router VM (the failure mode here)
vmstat 1 5                      # gu / sy columns
cat /proc/pressure/cpu
systemctl show s-router-cobalt-prod-vm.service -p CPUAffinity -p Nice
# zram exposure (no mem_limit on this kernel => no ceiling)
zramctl; cat /sys/block/zram0/mm_stat
ls /sys/block/zram0/mem_limit   # ENOENT => unbounded
```

### Protected paths

- `prod-network/{prod,testing,current}/` are near-duplicate large trees
  (`intent.nix` alone is ~3.6k lines each, with matching inventory and per-device
  SOPS secrets). These paths are protected: do not read, edit, or move them
  without explicit, per-session permission naming the exact files. The
  duplication is recorded only so a single-source-of-truth design can be
  proposed deliberately later; do not act on it as a side effect of unrelated
  work. The table in "Host naming (routers)" was derived from host files and
  `flake.lock`, not by editing these trees.

### Build distribution and shared binary cache

The fleet rebuilds work that another host has already done. Builds are already
centralized onto the remote builders (s-sigma / s-tau, ssh-ng + binfmt), but the
resulting store paths never flow back to the other hosts as substitutable
artifacts, so each host rebuilds the same flake outputs locally.

Two things are true today and both matter for the design:

- `services.nix-serve` exists but is **not enabled anywhere**. The module
  `nixos/server/{s-sigma,s-tau}/cache-for-vms-and-lxc-containers/default.nix` is
  not imported by either host, and `/etc/nix/nix.conf` on s-sigma lists no
  loopback substituter, so nothing is being served. The module is also an
  unfinished sketch (it generates the signing key with a `make-key` service on
  every boot, which would invalidate all previously signed paths).
- Every physical host already reaches the builders over nebula for *building*,
  so the path for *substituting* is already there.

### The dedicated build-and-cache VM

**Status: proposal only. Nothing in this section exists in the repo yet** — no
`s-cache` host config, no `services.nixosShellVmManager` entry, no signing key in
SOPS, no `binary-cache.nix` profile.

The preferred shape is one dedicated guest on the big builder, not the hypervisor
root store. Working name `s-cache`: a new nixos-shell VM on s-sigma that would be
declared through `services.nixosShellVmManager` alongside the existing guests
(e.g. `s-router-prod`) so it is managed, restarted and supervised the same way.
Standing it up is step 12 of the action list.

Why a guest rather than serving s-sigma's own `/nix`:

- **Blast radius.** A prebuild/warm job that misbehaves can only fill the
  guest's disk, not the hypervisor's root store. Keeping a multi-hundred-GB
  fleet closure out of `/nix` on s-sigma also avoids fighting the host's GC.
- **Independent GC policy.** The cache can pin and retain fleet closures without
  changing when s-sigma collects its own garbage.
- **It is a real NixOS config**, so it is reproducible and rebuildable from this
  repo instead of a hand-tuned host directory.
- **Two failure domains.** s-sigma can reboot or reinstall without taking the
  cache with it — the guest is a store path, so it comes back.

Trade-offs to accept knowingly: the guest needs its own disk (a `virtio` disk on
`/persist`, sized to the fleet closure, NOT a bind-mount of the host store), and
it duplicates anything it builds rather than sharing s-sigma's already-built
paths. Mitigate the duplication by making s-sigma a substituter *for the guest*,
so the guest pulls instead of rebuilding what the host already has.

Resource shape (s-sigma measured: **64 cores, 503 GiB RAM, 2.7 TiB free on
`/persist`**):

- **Never 100%.** The intent is a cache that fills gradually, not a second
  build farm competing with interactive work and the router VMs. Cap the guest
  at a fraction of the host and cap Nix *inside* it independently:
  - guest `cores = 12` (of 64) and `memory = 48G` (of 503 GiB) — leaves the
    hypervisor, the router VMs and the interactive load untouched;
  - inside the guest, `nix.settings.max-jobs = 4` and `cores = 3`, so one
    rebuild cannot explode into 12-wide parallelism;
  - `systemd` `CPUQuota=75%` on the warm service and
    `IOSchedulingClass=idle` / `Nice=19`, so it yields to everything else;
  - this is the 80% rule in practice: **use at most ~80% of an allocated slice,
    and allocate a slice well under the host.** Never size the guest to the
    whole machine and rely on `nice` to save you.
- **Disk sizing.** Start at ~500 GiB for the guest store; measure the real fleet
  closure (`nix path-info -Sh ./result` summed over hosts) before committing to
  a size. s-sigma has 2.7 TiB free, so this is cheap to be generous with.

### Making it actually serve: the pieces

1. **Sign the cache once, with a key that persists.** Generate one keypair,
   store the private half in SOPS under the existing shared-secret convention
   (`secrets/general-*.yaml`, whose `.sops.yaml` rule already encrypts to every
   host key), and install it at a stable path. **Do not** regenerate per boot —
   every path signed by a previous key becomes untrusted. The existing
   `make-key` service in the VM/LXC module is exactly the bug to avoid.
2. **Serve over nebula, not loopback.** `services.nix-serve.enable = true` in the
   guest, bound to the guest's nebula address, with `secretKeyFile` pointing at
   the SOPS-installed key. Clients reach it as `http://100.64.0.<x>:5000`.
   The loopback-socket-plus-socat arrangement in the old module was a workaround
   for VMs that could not reach the host's port; with the guest on nebula it is
   unnecessary.
3. **Subscribe every host** through one shared profile
   (`profiles/nixos/nix/binary-cache.nix`) that sets `extra-substituters` and
   `extra-trusted-public-keys`. This is the same mechanism already used for
   cache.nixos.org, numtide and the CUDA cache, so it composes with them.
4. **Warm on a timer, not on demand.** A systemd timer in the guest enumerates
   `nixosConfigurations.<host>.config.system.build.toplevel` plus the flake's
   packages and `nix build`s them, so the cache is warm before a laptop asks.
   Run it nightly and let it be slow (`CPUQuota`, idle IO) — that is the whole
   point of the 80% cap.
5. **Keep GC from evicting it.** Pin the fleet closure with a root or
   `nix-store --add-root`, or the guest's GC will delete exactly the artifacts
   the cache exists to serve.
6. **Clients must fail soft.** A cache that is down must degrade to "build
   locally", never to "cannot rebuild". Every host keeps its normal
   substituters and `fallback = true`.

### Multi-site build coordination

Two sites each run an R730 (s-sigma, s-tau) as a builder. Independent prebuild
timers on both would race: each enumerates the same fleet closure and starts the
same derivations concurrently, and nix-serve offers no claim/lock protocol, so
duplicate work is the default. The rule is: **one build authority, the rest are
mirrors and fallbacks.**

- **Single prebuild authority.** Only one server runs the prebuild timer and
  owns "build the fleet". The other site runs no timer; it is a cache consumer
  and a fallback builder for when the authority is unreachable.
- **Cache replication, not independent building.** The mirror site warms by
  pulling, never by building: either lazy (its hosts list the authority as a
  substituter and the mirror keeps what it fetches) or eager (a timer on either
  side runs `nix store copy` of the fleet closure to the mirror's store over
  ssh-ng).
- **Local-first substituter ordering.** Each site's hosts list their own local
  mirror before the remote one, and both before cache.nixos.org (which already
  has priority 40). The LAN mirror serves the common case; the nebula link to
  the other site only serves cache misses.
- **Fallback builds still dedupe.** Keep `builders-use-substitutes = true`:
  when the authority's cache is reachable the fallback builder downloads the
  result instead of rebuilding; it only builds when the authority has nothing
  to offer.
- **True race elimination needs a coordinator.** If per-commit status and a
  single dispatch queue become necessary, Hydra is the tool: one queue runner
  dedupes jobs and hands them to machines, so two builders can never start the
  same job. The timer approach above is a cheap approximation, not a
  distributed scheduler.

**Failure behaviour.** The single authority only owns *proactive warming*, not
build capability. If it is down, nothing stops: hosts keep building locally or
offload to the fallback server (`fallback = true`), and both sites' nix-serve
mirrors keep serving whatever is already in their stores. What is lost is warm-
cache progress, plus a small window for duplicate work: the fallback may build
paths on demand while the authority is away, and when the authority returns it
must not rebuild those same paths. Symmetric substituters close that gap — each
server lists the other, so whoever builds a path first, the other downloads it.
Promoting the fallback to authority is a manual decision (or a healthcheck-gated
timer); only a coordinator (Hydra) makes failover automatic without
reintroducing a race window.

## Target Layout (now largely realized)

The goal is not to make every host list every tiny file, and not to import one
huge bundle everywhere. Use the host root as a readable menu of small named
bundles:

```nix
{
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops

    profiles.nixos.base.default
    profiles.nixos.desktop.i3
    profiles.nixos.virtualization.libvirt
    profiles.nixos.virtualization.podman

    ./hardware
    ./connect-nas
    ./nixos-shell-servers
  ];
}
```

Boundaries:

- `nixos/`: only concrete machines and their local hardware.
- `profiles/nixos/`: reusable system profiles (desktop, server, virtualization
  host, impermanence, pentest, router VM host).
- `profiles/home-manager/`: reusable user profiles.
- `modules/nixos` / `modules/home-manager`: real option-bearing reusable modules.
- `pkgs/`: all local package derivations.
- `overlays/`: only package-set modifications that cannot be a package.
- `library/`: helpers only, once `library/01-general` is fully split.

### Convenience Bundles

Convenience bundles are still useful; the mistake is having one catch-all such
as `library/01-general/default.nix`. Prefer role-named bundles:

```nix
profiles.nixos.workstation.full = [
  profiles.nixos.base.default
  profiles.nixos.desktop.i3
  profiles.nixos.virtualization.libvirt
  profiles.nixos.virtualization.podman
  profiles.nixos.packages.workstation
];
```

A host can then import `profiles.nixos.workstation.full`, while `s-sigma`
imports only the subset it needs. If a host imports a bundle, the bundle name
should describe a real role, not just "general".

### Practical Rule Of Thumb

If a host file imports more than roughly 15 tiny shared files, introduce a named
profile. If a profile configures unrelated domains, split it.

Good names describe why a host wants them (`profiles.nixos.base.default`,
`profiles.nixos.desktop.i3`, `profiles.nixos.virtualization.libvirt`,
`profiles.nixos.workstation.pentesting`). Weak names hide intent (`general`,
`common`, `default`, `everything`).

`default.nix` is fine when it means "default for this specific role or
directory", not "all shared config in the repo".

### Use Module Export Sets

Keep populating `modules/nixos/default.nix` and
`modules/home-manager/default.nix` with stable named modules:

```nix
outputs.nixosModules.local-users
outputs.nixosModules.cuda-cache
outputs.homeManagerModules.editors-vscode
```

Hosts can still use relative paths, but exported names make reuse in tests, VMs,
and external flakes easier. `modules/nixos` already carries several; the gap is
`modules/home-manager`, which still has only `default.nix`.

## Overlays

### Overlay Policy

Use overlays only for package-set changes that must affect dependency resolution
inside nixpkgs:

- replacing a dependency inside another package;
- carrying a temporary upstream patch;
- exposing an alternate package set such as `pkgs.unstable`.

Do not use overlays for normal local packages. Put those in `pkgs/`.

Add a comment to every non-empty overlay stating what it changes, why it exists,
the upstream issue/PR if any, and the removal condition. `overlays/default.nix`
already aggregates through `additions`, `modifications`, `unstable-packages`,
and `nixpkgs-25_11-packages`; the two live workarounds emit their own runtime
warnings (`libvirt` credential overlay, `angr` from `pkgs.nixpkgs-25_11`), so
each needs an explicit removal condition.

### Unstable Package Set

`pkgs.unstable` is convenient but hides provenance. Standardize access:

- use `pkgs.unstable.<package>` for intentionally unstable packages;
- avoid ad hoc `import inputs.nixpkgs-unstable` in individual modules;
- if a module must choose stable versus unstable, make that explicit in the
  profile or module option.

## Packages

For host features that install a local package and configure system integration,
split package from module:

- derivation in `pkgs/<name>/default.nix`;
- NixOS module in `profiles/nixos/<feature>.nix` or `modules/nixos/<feature>.nix`.

Keep `burp-fix` host-local while it is only `l-envil`-specific `/etc` glue. If
it becomes a reusable wrapper or package, move the derivation into `pkgs/` and
keep the system integration in a profile or module.

## Home Manager

Shared Home Manager logic should live in one place. Either keep recognizable
profiles under `profiles/home-manager`, or under `home-manager/01-general`, but
do not split the shared surface across both without an explicit boundary.

Recommended grouping:

- `profiles/home-manager/base.nix`
- `profiles/home-manager/editors/vscode.nix`
- `profiles/home-manager/desktop-i3/default.nix`
- `profiles/home-manager/git/default.nix`
- `profiles/home-manager/virt-manager.nix`

`profiles/home-manager/` already carries `agents-all`, `claude-code`,
`deepseek`, `desktop`, `desktop-i3`, `desktop-sway`, `mail`, and `nix`. The
`home-manager/01-general` side of the split is the remaining work.

Host-specific user config should become mostly identity, secrets, and imports.

## Host Layout

Keep hardware and machine identity local:

```text
nixos/laptop/l-esp/
  default.nix
  hardware/
  services/
  home.nix
```

Keep reusable service stacks outside host directories unless truly single-host.
For servers, keep role modules explicit:

```text
nixos/server/s-sigma/
  default.nix
  hardware/
  roles/
    vm-host.nix
    nas-mounts.nix
    router-lab-host.nix
```

## Secrets

- Keep host SOPS file selection in the host root.
- Keep user SOPS file selection in the Home Manager root.
- Move repeated age key path conventions into small helper modules if identical
  across hosts.

Do not centralize secret names too early; centralize only repeated mechanics.
Any host rename in the plan above rewrites SOPS keys, so do renames and secret
path changes as one deliberate change, never interleaved with unrelated cleanup.

## Profile Boundary Notes From 2026-06-29 Audit

These were noticed while moving GUI applications out of NixOS package sets and
into Home Manager. The unresolved ones remain open work.

- Secure Boot tooling belongs in a boot profile, not core. `sbctl` should follow
  `boot.lanzaboote.enable`; key enrollment stays an explicit per-machine action.
  **Done:** `profiles/nixos/boot/secure-boot-tools.nix` owns `pkgs.sbctl` and is
  the only importer of it, reached from `profiles/nixos/laptop/intel-workstation.nix`
  and `profiles/nixos/server/dell-vm-host.nix`. (`pkiBundle` paths remain in
  host `hardware/` files, which is correct.) Do not re-add `sbctl` to core.
- Rich Neovim/LSP setup stays an editor profile, not a core dependency. `core`
  is imported by nixos-shell VM host configs, so editor-heavy profiles must
  attach only to interactive hosts that want them. Keep plain `vim` in core
  because nano is disabled and every machine needs a fallback editor.
- Xorg and i3 helper packages stay in desktop/i3 profiles, not core.
- Wireshark stays system-side (capture permissions/groups are NixOS concerns)
  but should sit behind a small workstation or pentest-capture profile.
- KDE Connect stays system-side where it enables `programs.kdeconnect`, but
  host-local duplicates should collapse into the Android workstation profile or
  an explicit KDE Connect profile. `profiles/nixos/workstation/android.nix` is
  the natural home.
- Desktop session plumbing stays NixOS-side (display manager, X11/i3, PAM/i3lock,
  dconf, keyring); browsers, chat clients, PDF readers, RDP clients, LLM GUIs,
  and torrent clients belong in Home Manager.
- NAS/CIFS client glue is a repeated host-local `connect-nas` module. Consider a
  storage/NAS client profile owning `cifs-utils`, mount defaults, and shared
  mechanics while secrets and endpoints stay host-local.
- Repeated `security.pam.services.login.enableGnomeKeyring = true` should become
  part of a desktop keyring profile.
- Host-local VM/nixos-shell support should keep moving toward clearly-named
  profiles; do not mix VM host plumbing, debug packages, network management, and
  persistence disks into a broad host root.
- `library/01-general/desktop/packages.nix` still mixes virtualization, desktop
  tools, CLI utilities, and privilege-bearing packages. Split or retire it before
  reusing it on new hosts. It is still reached via
  `library/01-general/default.nix` and individual imports.

## Staged Cleanup Plan

Do these in order. Step 0 is a prerequisite: later steps assume a trustworthy
`nix fmt`. None of these touch protected paths, except the router rename, which
is explicitly gated.

0. Make the formatter check enforceable, then clear the drift.
   Change the no-argument path in `flake.nix`'s `formatter` to run
   `nixpkgs-fmt --check .` (or `--fail-on-change`) so `nix fmt` and CI actually
   fail on unformatted files, and stop the explicit-file path from exiting 0 when
   it filtered everything out. Then format the whole-tree drift as a single
   isolated commit containing nothing else.

1. Resolve stale refs.
   Resolve both live stashes, starting with `stash@{1}` (`WIP intent revert`
   over protected `prod-network` intent), then prune the six stale local
   branches once it is confirmed nothing unique is lost. Keep `main` tracking
   `origin/main`.

2. Decide the dynamic-import question.
   `library/imports.nix` still provides directory-scanning discovery called from
   `home-manager/l-esp/configs/default.nix` and
   `nixos/laptop/l-esp/optional/default.nix`. Migrate those two call sites to
   explicit imports and retire the helper, or document the exception.

3. Finish the `library/01-general` split.
   39 imports over 21 files remain. Work largest-first: `network/ssids.txt` and
   `network/wifi-ssid-derive.sh` into a `profiles/nixos/network` owner;
   `system/autoupdate.nix` and `system/garbage-collection.nix` into
   `profiles/nixos/base/maintenance.nix`; `password-cracking` into
   `profiles/nixos/workstation`; `desktop/shell-env.nix` and
   `desktop/fonts.nix` into `profiles/nixos/desktop`; the `packages/*` leaves
   into `profiles/nixos/packages`. Delete `library/01-general/default.nix` with
   the last import.

4. Fold the window-manager leftovers.
   Move `library/02-window-manager-i3` into `profiles/nixos/desktop/i3.nix` and
   `library/03-window-manager-sway` into `profiles/nixos/desktop/sway.nix`, and
   repoint `nixos/virtual-machine/dedicated-vm/l-envil-llm-jail/default.nix` at
   the i3 profile. Delete both `library/` directories only after no importer
   remains.

5. Normalize unstable usage.
   Replace ad hoc `import inputs.nixpkgs-unstable` with `pkgs.unstable` or a
   single helper pattern across `overlays/unstable-packages.nix`,
   `home-manager/s-test-vm/home.nix`, and
   `library/01-general/packages/pentesting/packages.nix`.

6. Tighten exported module sets.
   Add stable names in `modules/home-manager/default.nix` (currently only
   `default.nix`) so it matches `modules/nixos`.

7. Remove stale files.
   Move `overlays/not-workingyet` and any remaining experiments to an archive
   directory or out of the flake source.

8. Decide the option convention.
   Write down whether the AGENTS.md `mkOption` / `enable` rule applies to new
   modules only or retroactively, and align the docs.

9. Update the README.
   Document the chosen import convention and point readers at this plan and
   AGENTS.md. Keep the note about the Misterio77 origin as context.

10. Add a PR-time `nix flake check` workflow.
    The scheduled flake-lock workflow already evaluates derivations; a push/PR
    check closes the loop for ordinary changes.

11. Router host naming to `<site>-<posture>` — **deferred, do not schedule now.**
    `s-router-prod` is the live neon-site router; renaming it while it is in
    service is a deploy-time identity change, not a refactor. Requires explicit
    per-session permission for `s-router-prod` and the `prod-network` trees, and
    should be folded into the next from-scratch rebuild of that host. When it is
    done: rename the host directory, update `hostSystems` and the `nixos-shell`
    mapping in `flake.nix`, update
    `productionSelector`/`selectorFile`/`networking.hostName`, and confirm SOPS
    routing keys still resolve. Validate by diffing rendered
    `system.build.toplevel` before and after — a pure rename must produce an
    identical derivation. See "Host naming (routers)".

12. Fleet binary cache via a dedicated build VM — **not implemented, design only.**
    Stand up `s-cache` as a supervised nixos-shell guest on s-sigma, with its own
    persisted store disk, a SOPS-held signing key installed at a stable path, and
    `services.nix-serve` bound to its nebula address. Cap it to a slice of the
    host (12 of 64 cores, 48 of 503 GiB, `CPUQuota=75%`, idle IO, `max-jobs = 4`
    inside) so it warms gradually and never saturates the machine. Add a nightly
    warm timer, pin the fleet closure against GC, and add the shared
    `profiles/nixos/nix/binary-cache.nix` profile to every host. Do this per site
    only after step 13 decides which site is the authority. See "Build
    distribution and shared binary cache" above.

13. Single build authority across sites.
    Run the prebuild timer on exactly one R730; make the other site a pull
    mirror (`nix store copy`) plus fallback builder, and order substituters
    local-first on every host. See "Multi-site build coordination" above.

14. One `profiles/nixos/hardware/memory.nix` for zram, swap, tmpfs and `vm.*`.
    Start with `l-esp` (it has measured evidence), then route `l-envil`,
    `l-portal` and `s-nodus` through it. Preserve the btrfs swapfile/scrub
    interaction in `l-esp/hardware/btrfs-scrub.nix` — it must stay out of
    whatever `services.btrfs.autoScrub.fileSystems` enumerates. Cap `/tmp`
    tmpfs explicitly while moving it, so the documented size lives with the
    rest of the memory policy rather than being implicit. zram sizing must be a
    per-host input, not a shared constant: `l-esp` runs 50%, `s-nodus` runs
    100% on a board that also gives 2048 MiB to a fixed guest. See "Memory
    reclaim policy is absent" and "s-nodus (100.64.0.18)" above.

15. Re-activate `s-nodus` from current HEAD and confirm the TSO guard lands.
    Generation 72 (`26.05.20261105.c56a87d`) predates the unit, so the board is
    running without its documented MT7988 TXD-ring mitigation. This is also the
    cheapest check that the aarch64 builder path still works. Gate on
    `nixos/server/s-nodus/network.nix`: make the offload unit assert the
    post-change `ethtool -k` state instead of ending every call in `|| true`, so
    a future rebuild that drops it fails loudly.

## Validation Strategy

For every cleanup step:

- Run `nix flake check --all-systems` when the build cost is acceptable.
- At minimum, run targeted evals:

```sh
nix eval .#nixosConfigurations.l-esp.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.l-envil.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.s-sigma.config.system.build.toplevel.drvPath
```

- For package changes, build the affected package directly.
- For Home Manager-only moves, eval the affected user config before rebuilding
  the host.

For the memory profile (step 14), the config eval proves nothing. Validate on
the host after activation:

```sh
# order-6 blocks must be non-zero after a day of normal use
tr -s ' ' < /proc/buddyinfo | grep Normal
dmesg | grep -c 'Tx queue alloc failed'          # expect 0, was 458
journalctl -b -k | grep -c 'page allocation failure'   # expect 0, was 313
grep -E 'SReclaimable|SUnreclaim' /proc/meminfo
grep -E 'compact_|allocstall' /proc/vmstat
```

For s-nodus (step 15), the config eval is not enough either — the whole finding
was that HEAD and the running system disagreed:

```sh
systemctl status mtk-eth-tso-off --no-pager | head -3   # must be active
sudo ethtool -k eth1 | grep -E 'tcp-segmentation-offload'  # must be off
readlink /run/current-system                             # must be the new drv
vmstat 1 5                                               # gu/sy after CPU policy
cat /proc/pressure/cpu
```

Concurrent `nix eval` runs contend on one eval cache and may emit an occasional
SQLite "database is busy" warning; that is benign.

## What Not To Do Yet

- Do not rename host directories while host discovery depends on direct
  subdirectories — except as the single, gated change in step 11.
- Do not rename `s-router-prod`. It is the live neon-site router; the naming
  inconsistency is documented here on purpose so it can be fixed at the next
  from-scratch rebuild, not against a running site.
- Do not convert everything into option-bearing modules at once.
- Do not move secrets during the import cleanup.
- Do not combine unrelated cleanup with package updates.
- Do not touch `prod-network/{prod,testing,current}/` without explicit,
  per-session permission naming the exact files.
- Do not re-add `library/01-general/default.nix`. It is being retired on purpose;
  a new host that needs much of it wants a `profiles.*` bundle instead.
- Do not leave a mixed commit that "also adds" or "also removes" a probe host
  stub alongside unrelated fixes; that pattern has silently undone deliberate
  removals twice.
- Do not "fix" wifi `Tx queue alloc failed` by changing `iwlwifi` module
  parameters before checking `/proc/buddyinfo`. The failure is memory
  fragmentation (see "Memory reclaim policy is absent" above); touching the
  driver hides the symptom and leaves the real leak in place.
- Do not set `vm.watermark_boost_factor` upward on hosts with `iwlwifi`. It
  already fires and fails there.
- Do not trust a comment in a host file as evidence a mitigation is active.
  `s-nodus/network.nix` declares the MT7988 TSO/GSO guard and it was absent from
  the running system for a month (`systemctl status mtk-eth-tso-off` -> not
  found, `ethtool -k eth1` -> `tx-tcp-segmentation: on`). Verify against
  `/run/current-system`, not against git.
- Do not size `zramSwap.memoryPercent` as a fraction of *total* RAM on a host
  that also hosts a fixed-size VM. s-nodus runs a 2048 MiB guest on 3.8 GiB and
  sizes zram at 100%; `/sys/block/zram0/mem_limit` does not exist on that
  kernel, so there is no ceiling.

## Desired End State

The repo should make these questions easy to answer:

- Which machines exist?
- Which profiles does each machine use?
- Which packages are local to this flake?
- Which overlays are active, and why?
- Which modules are reusable outside this repo?
- Which files are host-specific hardware or secrets glue?

The next concrete action is step 0 above: make `nix fmt` enforce something, then
clear the formatter drift and the two stashes before finishing the
`library/01-general` split one host at a time.
