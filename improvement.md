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
  from `home-manager/l-esp/projects/default.nix` and
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

The fix is a fleet-wide binary cache, not new builders:

- **Cache = the builders' own stores, served over HTTP.** `services.nix-serve`
  already runs on s-sigma/s-tau but is scoped to VMs/LXC via a loopback socket.
  Rebind it to the nebula overlay IP so every physical host can read it. No
  separate cache directory is needed.
- **Warm it ahead of demand.** A systemd timer on each builder prebuilds every
  `nixosConfigurations.<host>.config.system.build.toplevel` and flake package,
  so the cache is populated before a laptop asks. (Hydra is the heavyweight
  version of this: jobset -> builds -> cache; adopt it only if we want
  per-commit status, logs, and a UI.)
- **Subscribe every host.** Add `extra-substituters` (the two builder URLs) and
  `extra-trusted-public-keys` (the two cache public keys, committed to the repo)
  in a shared profile imported by all hosts. This is the same mechanism already
  used for cache.nixos.org, numtide, and the CUDA cache.
- **Signing trust model.** One signing keypair per builder; only the public keys
  are shared. A host downloads only from caches whose key it lists.
- **Keep GC from evicting the cache.** Pin the fleet closure (or protect cached
  paths) on the builders, or a `nix-collect-garbage` wipes the prebuilt
  artifacts.
- **Builders must also consume the cache.** With the cache in the substituter
  list and `builders-use-substitutes = true` (already set), s-sigma and s-tau
  download each other's results instead of rebuilding.

Optional variant: a real shared cache directory on the NAS
(`nix copy --to file:///mnt/nas/nix-cache`, nix-serve pointed at that dir).
Reach for it only if the cache should live off the servers' disks; SMB is a more
fragile live-cache backing store than serving the local store.

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
   `home-manager/l-esp/projects/default.nix` and
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

12. Fleet binary cache.
    Rebind `services.nix-serve` on s-sigma/s-tau to the nebula overlay IP, add
    a prebuild timer, and add a shared `profiles.nixos.nix.binary-cache` profile
    with the builder URLs and public keys for every host. See "Build
    distribution and shared binary cache" above.

13. Single build authority across sites.
    Run the prebuild timer on exactly one R730; make the other site a pull
    mirror (`nix store copy`) plus fallback builder, and order substituters
    local-first on every host. See "Multi-site build coordination" above.

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
