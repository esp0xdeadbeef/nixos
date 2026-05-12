# s-router-hetzner-anywhere Regression State

Last updated: 2026-05-12 00:55 UTC.

This file is current-state evidence only. Older entries are stale until
reverified.

## Fixed and Live-Verified

- Hetzner validation cleanup is currently verified through the repo watchdog
  script. It deleted the last aborted validator server and floating IPs, then a
  second immediate watchdog run finished with no visible resources remaining.

## Fixed but Only Locally Tested

- `network-codex-agent` now runs future Hetzner deploy commands in an
  interactive tmux bash shell instead of hiding them behind a non-interactive
  child script.
- `network-codex-agent` dry-run verified the dedicated tmux-session behavior:
  `hetzner-deploy-DRYRUN` accepted Ctrl-C, returned to an interactive shell,
  and wrote `/tmp/hetzner-deploy-dryrun-after-ctrl-c.txt` afterward.
- `network-codex-agent` now builds the expected reused-validator toplevel
  through the correct flake attr
  `#nixosConfigurations.s-router-hetzner-anywhere.config.system.build.toplevel`
  and provisions temporary build swap before the remote build/rebuild path.
  Focused guard passed:
  `bash tests/test-s-router-test-hetzner-deploy-guards.sh`.

## Implemented but Not Yet Live-Validated

- Local NixOS runtime files contain generated Hetzner facts from the aborted
  run; they are runtime state, not production evidence.

## Still Broken

- External prod-like validation is red. Full-loop run
  `2026-05-12 00:55 UTC` reused Hetzner server `130500355` and started
  dedicated tmux session `hetzner-deploy-130500355`, but remote
  `nixos-rebuild boot --flake path:/root/s-router-test-nixos#s-router-hetzner-anywhere`
  failed while building the toplevel:
  `died with <Signals.SIGKILL: 9>`.
- This SIGKILL path is patched but not live-validated yet.
- Public-WAN reachability, host firewall behavior, Nebula handshake,
  DNS-over-overlay, route selection, and leak-prevention checks are not
  verified on that validator.

## Pending / Unknown

- Whether the reused validator has enough memory/swap for the remote build, or
  whether the deploy path must avoid remote build pressure for this workflow.

## Next Concrete Debugging Target

- Inspect the preserved Hetzner deploy log for the SIGKILL root cause, then
  rerun the full loop only after the deploy path cannot die silently during the
  remote toplevel build.

## Assumptions in the Wrong Layer

- Hetzner public addresses, delegated prefixes, generated passwords, and other
  provider facts remain runtime/SOPS state. They must not be committed into
  model source.
