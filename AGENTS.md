# NixConfig Conventions for LLMs

## Commit Messages

Conventional commits: `type(scope): description`

- `type`: `feat`, `fix`, `refactor`, `chore`, `WIP`
- `scope`: path-based, reflecting what part of the config changed. Examples:
  - `home-manager/{feature}` for home-manager features
  - `{host}` or `{host}/{service}` for host-specific: `l-envil`, `l-esp/ollama`, `s-tau/disko`
  - Just the component for shared/global: `overlays`, `impermanence`, `nebula`
- Message is lowercase, no period at end.

## Directory Structure

```
.
├── home-manager/           # Home Manager user config per host
│   ├── 01-general/         #   Shared feature modules (desktop, editors, etc.)
│   ├── 02-window-manager-i3/
│   ├── 03-window-manager-sway/
│   ├── {hostname}/         #   Per-host config
│   │   ├── home.nix        #     Entry point
│   │   └── ...
├── nixos/                  # NixOS host configs
│   ├── laptop/             #   {l-hostname} hosts
│   │   └── {hostname}/
│   │       ├── default.nix
│   │       └── hardware/
│   ├── server/             #   {s-hostname} hosts
│   │   └── {hostname}/
│   └── virtual-machine/    #   VM hosts (nixos-shell-vm/, dedicated-vm/, etc.)
│       └── {vm-name}/
├── library/                # Importable NixOS modules
│   └── 01-general/         #   Feature modules (packages/, network/, desktop/, etc.)
├── modules/                # Custom NixOS & HM modules (unused if using library/)
├── overlays/               # Package overlays and patches
│   ├── default.nix         #   Aggregates all overlays
│   ├── additions.nix       #   Custom packages from ./pkgs
│   ├── modifications.nix   #   Patched packages (xlayoutdisplay, libvirt, etc.)
│   ├── unstable-packages.nix  # pkgs.unstable with ollama/python workarounds
│   ├── nixpkgs-25_11-packages.nix  # pkgs.nixpkgs-25_11 for ruby 3.3 compat
│   ├── impermanence-module.nix     # Patched impermanence NixOS module wrapper
│   └── legcord-unstable-overwrite.nix  # legcord from unstable
├── pkgs/                   # Custom package derivations
├── patches/                # Patch files referenced by overlays
├── profiles/               # Composable config profiles
│   ├── default.nix         #   Registry of all profiles
│   ├── nixos/              #   NixOS profiles
│   └── home-manager/       #   HM profiles
├── secrets/                # SOPS-encrypted secrets
│   ├── hosts/              #   Host-specific secrets
│   └── common/             #   Shared secrets
├── prod-network/           # Network prod-pin scripts
├── .github/workflows/      # CI workflows
├── flake.nix               # Flake entry point
├── deploy.sh               # nixos-rebuild wrapper
└── .sops.yaml              # SOPS encryption keys
```

## Code Style

- **Formatter**: nixpkgs-fmt (`nix fmt` to run). ALWAYS format after edits. Never format unmodified files.
- **Indentation**: 2 spaces, no tabs.
- **Line endings**: LF, final newline, trimmed trailing whitespace.
- **Nix conventions**:
  - Top-level modules are functions taking `{pkgs, lib, config, inputs, ...}`.
  - Use `lib` from `nixpkgs.lib // home-manager.lib` (merged, already in `outputs.lib`).
  - Feature-flag modules use a `default.nix` with a boolean `enable` option gating imports.
  - Prefer `lib.mkOption` / `lib.mkEnableOption` for new options.
  - Overlays with external dependencies (inputs, relativeRepo) use a context wrapper: `{ inputs }: final: prev: { ... }`.
  - Plain overlays (no deps) are bare `final: prev: { ... }`.

## Secrets

- Managed with **sops-nix**, keys defined in `.sops.yaml`.
- Two types of secret files:
  - `secrets/common/` -- shared across hosts, encrypted to all host age keys.
  - `secrets/hosts/{hostname}/` -- per-host, encrypted to that host only.
- Both are also encrypted to the PGP key `7088C7421873E0DB97FF17C2245CAB70B4C225E9`. It lives on misterio's yubikey.
- **Never** read secret values into context. Ask the user to read them, or use
  pipes and redirection so they do not appear in model-visible output, process
  arguments, or command history.
- When writing SOPS secrets through a pipeline, verify success without revealing
  the values. For example, check exit statuses and compare byte counts or hashes
  (`wc`, `sha256sum`) while keeping secret-bearing output out of context.

## Pre-push Privacy Checks

- **Never** commit or publish an unredacted public IPv4 address or an IPv6
  address from the current public subnet.
- RFC1918 IPv4 addresses and IPv6 ULA addresses are private infrastructure and
  are allowed; do not treat them as public-address findings.
- Before every push, discover the current public addresses without printing them
  (`curl -4 -fsS https://ifconfig.me` and
  `curl -6 -fsS https://ifconfig.me`). Check the exact IPv4 address and derive
  the IPv6 network using the known delegated prefix, or conservatively `/64`
  when the delegated prefix is unknown. Normalize candidate IPv6 addresses and
  test subnet membership; a textual prefix grep alone is insufficient.
- Build a private denylist through pipes from the relevant decrypted SOPS files.
  Include personal names, account and email local parts, domains, email
  addresses, hostnames, public IP addresses, and other identity-bearing values.
  Do not hardcode that denylist in this file or expose its values in
  model-visible output, process arguments, command history, or insecure temporary
  files.
- Before every push, scan case-insensitively across the complete candidate tree,
  every outgoing commit, and staged changes for the public addresses and private
  denylist. Report only redacted file and line locations; never print the matched
  value.
- The versioned `.githooks/pre-push` performs this scan. Keep
  `core.hooksPath = .githooks`, do not bypass the hook, and treat an incomplete
  scan as a failed push.
- Verify that SOPS files being pushed remain encrypted and that no derived secret
  value occurs in plaintext outside encrypted SOPS data. If address discovery,
  SOPS decryption, or any scan is incomplete, fails, or finds a match, stop and
  do not push.

## Checking

- Format touched Nix files with `nix fmt` (runs nixpkgs-fmt on all .nix files, or on explicit file args).
- Run `nix flake check --all-systems` after meaningful Nix changes.

Do not run `nixos-rebuild switch`, deploy scripts, or other apply/deploy commands
unless the user explicitly asks for that.

## Nix eval

When verifying config output before deploying:

- NixOS config: `nixosConfigurations.<host>.config.<path>`
- Home-manager (managed by NixOS): `nixosConfigurations.<host>.config.home-manager.users.<user>.<path>`
- Specialised HM variant: `nixosConfigurations.<host>.config.home-manager.users.<user>.specialisation.<variant>.config.<path>`
- `nix build <path>.source --no-link --print-out-paths` to get the built file
- `nix eval <path> --json` to inspect raw attribute values
