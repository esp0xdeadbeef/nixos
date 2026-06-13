# NixOS Repo Improvement Plan

This is a planning note only. Do not implement these changes while the current
repository changes are still being validated.

## Current Structure

The root README says this repository was originally private, was published later
because someone asked for it, and is based on Misterio77's
`nix-starter-configs`. That matters: the current structure should be treated as
an evolved personal workstation/server config, not as a deliberately designed
public framework. The cleanup should preserve working host behavior and reduce
surprise gradually.

The README also explicitly calls out the old ugly importer pattern:

```sh
(echo '{ pkgs, ... }: { imports = ['; find . -name 'build_*' -prune -o -name '*.nix' ! -name 'default.nix' -print; echo ']; }') | nixfmt | tee ./default.nix
```

That explains why several directories look like generated import surfaces and
why `build_*` files are scattered around. The improvement plan should replace
that importer workflow with explicit, named profile imports, not just rearrange
files.

The repository is flake-based. `flake.nix` owns host discovery and creates every
`nixosConfigurations` entry automatically from direct subdirectories under:

- `nixos/laptop`
- `nixos/server`
- `nixos/virtual-machine/nixos-shell-vm`
- `nixos/virtual-machine/dedicated-vm`
- `nixos/virtual-machine/nixos-anywhere`

Each discovered host gets only its host directory imported as the root NixOS
module. Shared context is passed through `specialArgs`, including `inputs`,
`outputs`, `self`, `name`, and `outPath`.

The repo currently has these broad areas:

- `nixos/`: concrete host definitions, hardware, service stacks, VM definitions,
  install notes, and host-local experiments.
- `home-manager/`: per-user Home Manager configs plus some shared Home Manager
  snippets under `home-manager/01-general` and `home-manager/02-window-manager-i3`.
- `library/`: shared NixOS configuration bundles and helper modules.
- `modules/nixos` and `modules/home-manager`: exported module placeholders, but
  currently mostly empty.
- `overlays/`: overlay exports, currently `additions`, `modifications`, and
  `unstable-packages`.
- `pkgs/`: flake package export point, currently mostly empty.
- `secrets/`: SOPS data and key-management notes.
- `start-pentest-tbd-where-to-put/`: separate flake/tooling area.

## Main Problems

The repo works, but boundaries are blurry:

- Some structure came from a starter template, while later host-specific work was
  added pragmatically. The result is understandable historically, but there is
  no longer one obvious convention for where a reusable thing should live.
- `library/01-general/default.nix` imports a very large set of NixOS modules.
  It mixes desktop, network, package lists, secrets, system defaults,
  virtualization, terminal config, time, and service assumptions.
- Host files import both true host hardware and higher-level profiles directly.
  This makes it harder to see what is host-specific versus reusable.
- Some reusable modules live in `library/`, some in `home-manager/01-general`,
  while exported module directories under `modules/` are nearly empty.
- Local packages such as `mxbuild`, `azurehound`, and pentest PowerShell tooling
  live under `nixos/laptop/l-werk/1-custom-packages`, even though they are really
  packages or package-backed modules.
- Overlays are used both for actual overlays and for injecting `pkgs.unstable`.
  That pattern works, but makes package provenance less explicit.
- There are old, backup, and experimental files mixed into active trees:
  `z_old`, `*.bak`, `not-workingyet`, `build_*`, and TODO-named directories.
- `library/default.nix` currently duplicates the legacy edge assertion module
  content instead of acting as the root library index. That is surprising and
  should be fixed in a cleanup branch.
- The generated-importer mindset makes it easy to add files and hard to know
  whether a file is intentionally imported, accidentally imported, or dead.

## Proposed Target Layout

The goal is not to make every host list every tiny file. That becomes noisy and
defeats the point of having reusable config. The goal is also not to import one
huge `default.nix` everywhere, because then hosts silently receive capabilities
they do not need.

Use the host root as a readable menu, and make the menu items small named
bundles:

```nix
{
  imports = [
    # External modules
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops

    # Shared profiles
    profiles.base
    profiles.desktop.i3
    profiles.virtualization.libvirt-host
    profiles.virtualization.podman

    # Host-local modules
    ./hardware
    ./connect-nas
    ./nixos-shell-servers
  ];
}
```

That is the balance to aim for:

- the host config is explicit about intent;
- the host config does not contain a long list of implementation files;
- shared bundles are narrow enough that their names mean something;
- broad convenience bundles are allowed, but only when the name truly matches
  the host.

Aim for a structure where a host says:

```nix
{
  imports = [
    profiles.base
    profiles.desktop.i3
    profiles.virtualization.host
    roles.laptop
    ./hardware
    ./services
    ./home.nix
  ];
}
```

The exact names can change, but the important boundary is:

- `hosts/` or current `nixos/`: only concrete machines and their local hardware.
- `profiles/nixos/`: reusable system profiles, such as desktop, server,
  virtualization host, impermanence, pentesting workstation, router VM host.
- `profiles/home-manager/`: reusable user profiles, such as editors, i3, git,
  PDF tools, virt-manager settings.
- `modules/nixos/`: real option-bearing reusable NixOS modules.
- `modules/home-manager/`: real option-bearing reusable Home Manager modules.
- `pkgs/`: all local package derivations.
- `overlays/`: only package-set modifications that cannot be represented as
  packages.
- `lib/` or `nix/lib/`: helper functions for host discovery, import generation,
  package helpers, and option helpers.

### Convenience Bundles

Convenience bundles are still useful. The mistake is having only one huge bundle
such as `library/01-general/default.nix`.

Better:

```nix
profiles.workstation.default = [
  profiles.base
  profiles.desktop.i3
  profiles.virtualization.libvirt-host
  profiles.virtualization.podman
  profiles.packages.workstation
];
```

Then a real workstation can import `profiles.workstation.default`, while
`s-sigma` can import only the subset it needs. If a host imports a convenience
bundle, the bundle name should describe a real role, not just "general".

For `s-sigma`, a good first target would be something like:

```nix
imports = [
  profiles.base
  profiles.desktop.i3
  profiles.virtualization.libvirt-host

  ./hardware
  ./connect-nas
  ./nixos-shell-servers
];
```

This keeps `s-sigma/default.nix` compact, but it no longer has to inherit every
desktop/workstation/pentest package from a generic catch-all import.

## Imports

### Current Import Style

Current host configs import many paths directly. Example patterns:

- `${outPath}/library/01-general`
- `${outPath}/library/02-window-manager-i3`
- local `./hardware`, `./connect-nas`, `./llms`, etc.
- direct Home Manager module imports inside each user config.

This is simple, but it scales poorly because `library/01-general` is too broad.
Every host that imports it gets desktop packages, virtualization packages, and
other assumptions whether it needs them or not.

The README's generated importer command also hints at a previous approach where
directory content determined imports automatically. That is fine during early
personal config growth, but long term it makes review and rollback harder.
Imports should become intentional API boundaries.

### Improve Import Boundaries

Split broad bundles into focused profiles:

- `profiles/nixos/base`: locale, nix settings, gc, common CLI tools, SSH defaults.
- `profiles/nixos/desktop`: fonts, XDG portal, screen recording, desktop packages.
- `profiles/nixos/i3`: i3/Xorg-specific system dependencies.
- `profiles/nixos/virtualization-host`: libvirt, docker/podman/lxc, virt packages.
- `profiles/nixos/pentest`: pentest package set and wordlists.
- `profiles/nixos/impermanence-workstation`: shared impermanence patterns, with
  host-specific file lists kept per host.
- `profiles/nixos/server`: server defaults, no desktop assumptions.
- `profiles/home/editors`: shared VS Code/VSCodium policy.
- `profiles/home/i3`: shared i3 Home Manager config.

Then make hosts import profiles by intent rather than importing the whole
`library/01-general` bundle.

This does not require abandoning the Misterio77-style flake structure. Keep the
good parts from the starter pattern: flake outputs, `nixosConfigurations`,
overlays, packages, and module exports. The improvement is to make the imports
semantic rather than generated from directory contents.

### Practical Rule Of Thumb

If a host file imports more than roughly 15 tiny shared files, introduce a named
profile. If a profile configures unrelated domains, split it.

Good profile names describe why a host wants them:

- `profiles.base`
- `profiles.desktop.i3`
- `profiles.virtualization.libvirt-host`
- `profiles.packages.pentest`
- `profiles.server.vm-host`

Weak profile names hide intent:

- `general`
- `common`
- `default`
- `everything`

Some `default.nix` files are still fine, but they should mean "default for this
specific role or directory", not "all shared config in the repo".

### Use Module Export Sets

Populate `modules/nixos/default.nix` and `modules/home-manager/default.nix` with
named modules. This gives stable names:

```nix
outputs.nixosModules.virtualization-host
outputs.homeManagerModules.editors-vscode
```

Host configs can still use relative paths, but exported names make it easier to
reuse modules in tests, VMs, or external flakes.

## Overlays

### Current Overlay State

`overlays/default.nix` exposes:

- `additions`: imports packages from `pkgs/`.
- `modifications`: currently empty.
- `unstable-packages`: adds `pkgs.unstable`.

The removed `certipy-ad` overlay is a good example of an overlay that was useful
temporarily but should not live forever once upstream is fixed.

### Overlay Policy

Use overlays only for package-set changes that must affect dependency resolution
inside nixpkgs. Examples:

- replacing a dependency inside another package;
- carrying a temporary upstream patch;
- exposing an alternate package set such as `pkgs.unstable`.

Do not use overlays for normal local packages. Put those in `pkgs/`.

Add comments for every non-empty overlay:

- what it changes;
- why it exists;
- upstream issue or PR if available;
- removal condition.

Example:

```nix
modifications = final: prev: {
  # TODO(remove after nixpkgs#123456 reaches nixos-26.05):
  # Fix foo runtime dependency mismatch.
  foo = prev.foo.overrideAttrs (...);
};
```

### Unstable Package Set

The `pkgs.unstable` overlay is convenient, but it hides provenance. Keep it if it
is useful, but standardize access:

- Use `pkgs.unstable.<package>` for intentionally unstable packages.
- Avoid ad hoc `import inputs.nixpkgs-unstable` in individual modules.
- If a module must choose stable versus unstable, make that explicit in the
profile or module option.

## Packages

### Move Host-Local Packages Into `pkgs/`

These should be moved out of `nixos/laptop/l-werk/1-custom-packages`:

- `mxbuild`
- `azurehound`
- pentest PowerShell bundle, if it is still wanted
- possibly `burp-fix` if it becomes a package or wrapper rather than only `/etc`
  file links

Recommended shape:

```text
pkgs/
  default.nix
  mxbuild/
    default.nix
  azurehound/
    default.nix
  pentest-powershell/
    default.nix
```

Then expose them from `pkgs/default.nix`:

```nix
pkgs: {
  mxbuild = pkgs.callPackage ./mxbuild { };
  azurehound = pkgs.callPackage ./azurehound { };
}
```

Host modules should consume them as `pkgs.mxbuild`, not import derivations from a
host-local path.

### Package-Backed Modules

For host features that install a local package and configure system integration,
split package and module:

- package derivation in `pkgs/mxbuild/default.nix`;
- NixOS module in `profiles/nixos/mendix-build.nix` or
  `modules/nixos/mxbuild.nix`.

This prevents package build logic from being hidden inside host config.

## NixOS-Shell VM Host Profile

The `s-sigma` nixos-shell setup is useful enough that it should probably become
a reusable host profile, but it does not need to be fixed immediately. Time is a
constraint, and the current implementation works.

Current shape:

- `nixos/server/s-sigma/nixos-shell-servers/default.nix` imports `servers.nix`.
- `servers.nix` is the inventory: it calls `mkVM "s-infra" { ... }`,
  `mkVM "s-nebula" { ... }`, etc.
- `mk-nixos-shell-vm.nix` contains the generic systemd/tmux/QMP/image-management
  machinery.
- `self.lib.vmSourceForHost` in `flake.nix` builds a minimal source tree for a
  selected VM host by excluding the other host directories.
- `library/10-vms/nixos-shell-vm/1-helpers` contains reusable guest-side helpers
  for persistence, SSH auth, networkd bridges, and debug packages.

That means the implementation is already split into two concepts:

- generic VM-host machinery;
- `s-sigma`'s chosen VM inventory.

The improvement is to make that boundary explicit.

### Desired Shape

Create a reusable NixOS profile or module for "this machine can host
nixos-shell VMs":

```nix
profiles.nixos.vm-host.nixos-shell
```

or, if it grows options:

```nix
modules.nixos.nixos-shell-vm-host
```

Then hosts can opt in explicitly:

```nix
{
  imports = [
    profiles.base
    profiles.virtualization.libvirt-host
    profiles.vm-host.nixos-shell

    ./hardware
    ./vm-inventory.nix
  ];
}
```

The host should still choose its inventory. Do not make every host run every VM
just because the profile exists.

### Suggested Module Boundary

Long term, wrap `mkVM` behind options:

```nix
services.local.nixos-shell-vm-host = {
  enable = true;

  defaults = {
    workingDir = "/persist/nix-shell-vms";
    persistDir = "/persist/vm-persists";
    stateDiskSize = "100G";
    ephemeralRoot = true;
  };

  vms = {
    s-infra = { description = "Infra VM"; };
    s-nebula = { description = "Nebula VM"; };
    s-router-legacy-edge = { description = "Legacy edge router"; };
  };
};
```

The module can translate `vms` into the existing `mkVM` calls. That preserves the
working implementation while making host intent clearer.

### Keep Inventory Separate

The host root should say it is a VM host, but the VM list should remain a local
file:

```text
nixos/server/s-sigma/
  default.nix
  vm-inventory.nix
  hardware/
```

For another host, such as `l-werk` or `l-esp`, enabling the profile later should
be a small change:

```nix
imports = [
  profiles.vm-host.nixos-shell
  ./vm-inventory.nix
];
```

This gives a clear overview:

- `default.nix` says the machine is capable of hosting nixos-shell VMs.
- `vm-inventory.nix` says which VMs this machine actually hosts.
- the shared module owns systemd/tmux/image logic.

### What To Avoid

- Do not move all VM definitions into one global file that every host imports.
  That recreates the current "too broad default" problem.
- Do not force a fully generic option module before the current setup is stable.
  A thin profile that imports the existing `mkVM` machinery is enough for a first
  step.
- Do not mix guest configuration and host launcher configuration. Guest configs
  belong under `nixos/virtual-machine/nixos-shell-vm`; host launcher inventory
  belongs under the host that runs them.

### Practical First Step

The low-effort step still has operational risk. If `s-sigma` VM hosting breaks,
the impact is high. So the first migration should be copy-first, test-first, and
easy to roll back.

Safer order:

1. Copy `nixos/server/s-sigma/nixos-shell-servers/mk-nixos-shell-vm.nix` to the
   future shared location, for example
   `profiles/nixos/vm-host/nixos-shell/mk-vm.nix` or
   `modules/nixos/nixos-shell-vm-host/mk-vm.nix`.
2. Leave `s-sigma` still using its current local
   `nixos-shell-servers/mk-nixos-shell-vm.nix`.
3. Add a cheap equivalence check or one-off eval comparing the generated attrs
   from the local and copied implementations. At minimum, compare generated
   service names, timer names, and `system.build.vmImages` attrs for a single
   non-critical VM.
4. Switch only a non-critical test VM or newly added VM to the shared helper
   first. Do not start with router/core infrastructure.
5. Once the shared helper has evaluated cleanly, switch `s-sigma/servers.nix` to
   import the shared path.
6. Keep the old local helper for one full rebuild/reboot cycle as a rollback
   target. Delete it only after the host has proven stable.
7. Rename `servers.nix` to `vm-inventory.nix` only after the helper move is no
   longer in question.
8. Only after that, consider adding proper options.

The rollback path must be: change one import path back. It should not require
debugging a new generic module while the VMs are down.

That gives reuse without forcing a big refactor and without betting the working
`s-sigma` VM host on the first cleanup step.

## LLM Workstation Profiles

The LLM-related modules are another obvious place where the repo should become
easier. The current setup works, but the intent is split across host-local files:

- `nixos/laptop/l-esp/llms/default.nix`
- `nixos/laptop/l-esp/llms/ollama.nix`
- `nixos/laptop/l-esp/llms/lmstudio.nix`
- `nixos/laptop/l-werk/llms/ollama.nix`
- `nixos/laptop/l-werk/llms/lmstudio.nix`
- `nixos/laptop/l-werk/llms/web-ui-ollama.nix`

The repeated concepts are:

- install LM Studio;
- enable Ollama;
- choose CPU versus CUDA Ollama package;
- preload a model list;
- optionally expose Ollama on `0.0.0.0`;
- optionally allow port `11434` on selected firewall interfaces;
- optionally run Open WebUI backed by Ollama;
- persist Ollama and LM Studio state on impermanent hosts.

That is exactly the kind of config that should become a profile with a few host
choices, not a pair of copied host-local modules.

### Desired Shape

Use one shared LLM profile with options, or a small set of named profiles:

```nix
profiles.nixos.llm.ollama
profiles.nixos.llm.lmstudio
profiles.nixos.llm.open-webui
```

For the host, the import should remain readable:

```nix
imports = [
  profiles.llm.ollama
  profiles.llm.lmstudio
  profiles.llm.open-webui
];
```

If options are worth it, a local module could look like:

```nix
services.local.llm = {
  ollama = {
    enable = true;
    package = "cuda"; # or "default"
    host = "0.0.0.0";
    models = [
      "llama3.1:8b"
      "qwen2.5-coder:1.5b-base"
      "nomic-embed-text"
    ];
    firewallInterfaces = [ "podman0" ];
  };

  lmstudio.enable = true;

  openWebui = {
    enable = true;
    bind = "127.0.0.1:3000";
    dataDir = "/persist/var/lib/open-webui";
  };
};
```

This keeps the host decision explicit without making every host copy the same
Ollama service definition.

### Split Defaults From Host Choices

The model list is a host choice. Do not hide it inside a generic default unless
it is truly universal.

Better:

- shared profile defines how Ollama is configured;
- host defines which models it wants;
- a convenience model set can exist for common cases.

Example:

```nix
llmModelSets.default = [
  "llama3.1:8b"
  "qwen2.5-coder:1.5b-base"
  "nomic-embed-text"
];

llmModelSets.heavy = llmModelSets.default ++ [
  "deepseek-coder:33b"
  "nous-hermes2:34b"
];
```

Then `l-esp` can use a lighter set and `l-werk` can use a CUDA/heavy set.

### Package Selection

Avoid ad hoc imports of `inputs.nixpkgs-unstable` inside LLM modules. Prefer the
repo convention:

```nix
pkgs.unstable.ollama-cuda
pkgs.unstable.ollama
```

The module can select between them based on a simple host option:

```nix
package = if cfg.cuda then pkgs.unstable.ollama-cuda else pkgs.unstable.ollama;
```

This keeps unstable usage visible and consistent with the rest of the repo.

### Binary Caches For CUDA Packages

CUDA-backed LLM packages are not normal workstation packages operationally. If
`ollama-cuda`, CUDA-enabled Python packages, Hashcat, or similar packages miss
the binary cache, the laptop may try to build a large CUDA closure locally. That
is slow at best and can make validation risky while other repo changes are being
tested.

Binary cache configuration now lives in a small reusable NixOS module:

```nix
outputs.nixosModules.cudaCache
local.nix.cudaCache
```

It is also imported through `library/01-general` so hosts that already use the
shared library get the option definitions. The module auto-enables only when the
evaluated NixOS config declares the Nvidia driver or Nvidia kernel modules. This
means `l-esp` and `l-werk` get the CUDA cache automatically, while `s-sigma`
does not as long as Nvidia remains disabled there.

The current public CUDA cache configured by the module is:

```nix
nix.settings = {
  extra-substituters = [
    "https://cache.nixos-cuda.org"
  ];
  extra-trusted-public-keys = [
    "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
  ];
};
```

Use `extra-substituters`, not a replacement `substituters` list, so the normal
NixOS cache remains active. The old `cuda-maintainers.cachix.org` cache should
not be reintroduced without checking whether it is still current.

Private/local cache support is intentionally not part of this implementation.
There is no local cache running right now, so adding options for one would only
increase surface area without solving the current problem. If a private cache or
remote builder becomes useful later, design it as a separate Nix profile.

Do not hide this inside the Ollama service module itself. Package selection and
cache selection are related, but they are different decisions. A host should be
able to say "use CUDA Ollama" and separately say "trust the public CUDA cache".

Practical first step:

1. Keep the public CUDA cache module auto-enabled from declared Nvidia driver
   usage.
2. Test with `nix build --dry-run` for `l-esp` and `l-werk` to see whether
   `ollama-cuda` downloads or builds.
3. If cache misses still happen often, decide separately whether a remote builder
   or private cache is worth adding later.

### Persistence

Ollama persistence is currently entangled with impermanence comments and
host-specific file lists. Make the LLM profile declare the generic persistence
needs, but let hosts decide whether impermanence is active.

Useful defaults:

- persist `/var/lib/private/ollama` or the chosen Ollama home;
- persist `~/.lmstudio` for users that install LM Studio;
- persist `/var/lib/open-webui` when Open WebUI is enabled.

Be careful with DynamicUser and `/var/lib/private/ollama`: this is exactly the
kind of thing that should be tested on one host before generalizing.

### Open WebUI

Open WebUI should be a separate opt-in profile. It depends on the host wanting a
local web interface, and it introduces container state, ports, and persistence.

Good boundary:

- `profiles.llm.ollama`: the model server;
- `profiles.llm.open-webui`: UI container for hosts that want it.

Do not make Open WebUI part of the base Ollama profile.

### Practical First Step

Do not create a full option module first. Start by extracting the duplication:

1. Create `profiles/nixos/llm/lmstudio.nix` with only `environment.systemPackages
   = [ pkgs.lmstudio ];`.
2. Create `profiles/nixos/llm/ollama-base.nix` that enables Ollama but leaves
   package, host binding, and model list overridable by the host.
3. Keep `l-esp` and `l-werk` model lists in host-local files initially.
4. Move `l-werk`'s Open WebUI module to `profiles/nixos/llm/open-webui.nix`, but
   keep it opt-in.
5. After both laptops evaluate, consider a real `services.local.llm` option
   module.

This is low-risk because the first useful extraction is LM Studio: it is only a
package install and has no service or network behavior.

## Home Manager

The new shared VS Code/VSCodium module is the right direction:

```text
home-manager/01-general/editors/vscode.nix
```

Long term, either keep shared Home Manager profiles under
`home-manager/01-general`, or move reusable ones into
`modules/home-manager`/`profiles/home-manager`. Avoid splitting shared Home
Manager logic between multiple conventions unless the boundary is explicit.

Recommended grouping:

- `profiles/home-manager/base.nix`
- `profiles/home-manager/editors/vscode.nix`
- `profiles/home-manager/i3/default.nix`
- `profiles/home-manager/git/default.nix`
- `profiles/home-manager/virt-manager.nix`

Host-specific user config should become mostly identity, secrets, and imports.

## Host Layout

Keep hardware and machine identity local to each host:

```text
nixos/laptop/l-esp/
  default.nix
  hardware/
  services/
  home.nix
```

Keep reusable service stacks outside host directories unless they are truly
single-host. For example, `llms`, `android`, and `unmount-pentest-directory` may
be reusable workstation profiles if both `l-werk` and `l-esp` can use them.

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

SOPS wiring is spread per host and Home Manager user. That is acceptable, but can
be clearer:

- Keep host SOPS file selection in host root.
- Keep user SOPS file selection in Home Manager root.
- Move repeated age key path conventions into small helper modules if they are
  identical across hosts.

Do not centralize secret names too early; centralize only repeated mechanics.

## Staged Cleanup Plan

1. Inventory active imports.
   Use a script or `nix eval` to list every host and its imported top-level
   profiles. Compare this with the README's generated-importer TODO. Do not move
   files yet.

2. Create profile directories.
   Add empty or thin wrapper modules that re-export the current `library/*`
   modules without behavior changes.

3. Move local packages into `pkgs/`.
   Start with `mxbuild`, because it is a normal derivation and a clear example.
   Keep host behavior identical by replacing only the import path.

4. Split `library/01-general`.
   Break it into `base`, `desktop`, `virtualization-host`, `packages`, and
   `pentesting` profiles. Update one non-critical host first.

5. Normalize unstable usage.
   Replace ad hoc `import inputs.nixpkgs-unstable` with `pkgs.unstable` or a
   single helper pattern.

6. Populate exported module sets.
   Add stable names in `modules/nixos/default.nix` and
   `modules/home-manager/default.nix` after the profile names settle.

7. Remove stale files.
   Move `z_old`, `*.bak`, and experiments either to an archive directory or out
   of the flake source if they are not used.

8. Fix root `library/default.nix`.
   Make it a real index or delete it if unused. The current duplicate content is
   misleading.

9. Update the README.
   Replace the old importer TODO with the chosen import convention once the
   cleanup is real. Keep the note that the repo originated from
   Misterio77's starter configs, because that is useful context.

## Validation Strategy

For every cleanup step:

- Run `nix flake check` only when the build cost is acceptable.
- At minimum, run targeted evals:

```sh
nix eval .#nixosConfigurations.l-esp.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.l-werk.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.s-sigma.config.system.build.toplevel.drvPath
```

- For package moves:

```sh
nix build .#mxbuild
nix build .#azurehound
```

- For Home Manager-only moves, eval the affected user config before rebuilding
  the host.

## What Not To Do Yet

- Do not rename host directories while active host discovery depends on direct
  subdirectories.
- Do not remove `outPath`/`self.outPath` usage until all imports are migrated.
- Do not convert everything into option-bearing modules at once.
- Do not move secrets during the import cleanup.
- Do not combine unrelated cleanup with package updates.

## Desired End State

The desired repo should make these questions easy to answer:

- Which machines exist?
- Which profiles does each machine use?
- Which packages are local to this flake?
- Which overlays are active, and why?
- Which modules are reusable outside this repo?
- Which files are host-specific hardware or secrets glue?

The first concrete cleanup should probably be moving `mxbuild` into `pkgs/`,
because it is low-risk, self-contained, and demonstrates the package/module
boundary clearly.
