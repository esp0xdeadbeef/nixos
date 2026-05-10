# s-router-hetzner-anywhere Regression State

Last updated: 2026-05-10 17:56 UTC.

Current external pass: failed. The latest locked full-lab run installed NixOS
with `nixos-anywhere`, rebooted, and then never returned on SSH. Hetzner still
reported the server as running, but `ssh root@204.168.245.145` returned
`Connection refused`.
Console login with the generated `pw.txt` password showed the direct cause:
`sshd.service` failed because `/etc/ssh/sshd_config` did not exist.

## Fixed and Live-Verified

- Hetzner cleanup watchdog deletion is live-verified for the 2026-05-10
  floating-IP leak. After `pkill sleep`, the old watchdog deleted the server
  but left floating IPs `130193580` and `130193581`. The corrected watchdog
  explicitly unassigned/deleted remaining floating IPs and the Hetzner API then
  showed no servers and no floating IPs.
- Earlier manual CA/profile issuance proved `c-router-lighthouse` and
  `c-router-nebula-core` can start once `/persist/etc/nebula/config.yml`
  exists, but that is not a current automatic pass.

## Fixed but Only Locally Tested

- `network-codex-agent` refuses `nixos-rebuild switch` reuse unless the remote
  validator already has tmpfs `/`, btrfs `/nix`, and btrfs `/persist`.
- The cleanup watchdog re-queries Hetzner after deletion and exits non-zero if
  any matching server or floating IP remains visible.
- The cleanup watchdog now tolerates `pkill sleep` for every sleep in the
  script, not only the initial deadline sleep. It also retries deletion of all
  still-visible resources and explicitly unassigns floating IPs before
  deleting them. This covers both observed failures: interrupted later sleeps
  under `set -e`, and Hetzner 422 responses while server deletion is still
  detaching floating IPs.
- The full-lab loop now waits for the Hetzner deploy result before finalizing
  slower CLAB VM matrix jobs, so a real external deploy failure is not hidden.
- The interrupt path now exits through `main_cleanup`, so QEMU/CLAB/background
  job trees are terminated instead of only running Hetzner cleanup.
- A generated UUIDv4 root console password is now written to the local runtime
  `pw.txt`, while only a SHA-512 hash is copied into the Hetzner NixOS
  extra-files. SSH password authentication remains disabled. Focused checks:
  `tests/test-s-router-test-hetzner-console-password.sh`,
  `tests/test-s-router-test-hetzner-deploy-guards.sh`, and
  `tests/test-s-router-hetzner-impermanence-contract.sh`.
- Hetzner SSH impermanence now follows the working l-esp/l-werk/s-sigma
  pattern: do not persist `/etc/ssh` as a directory, because that hides the
  generated `/etc/ssh/sshd_config` on tmpfs root. Persist only OpenSSH host key
  files through `services.openssh.hostKeys` pointing at `/persist/etc/ssh`.
  Focused checks passed:
  `tests/test-s-router-hetzner-ssh-impermanence.sh` and
  `tests/test-s-router-hetzner-impermanence-contract.sh`.
- Focused cleanup logic checks passed:
  `tests/test-s-router-test-hetzner-cleanup-watchdog-pkill-sleep.sh`. It runs
  the watchdog against a fake Hetzner API with `sleep` forced to fail and the
  first floating-IP delete forced to fail, then asserts that server and
  floating IP deletes still happen.

## Implemented but Not Yet Live-Validated

- The Hetzner NixOS config is in impermanence mode: root is tmpfs, `/nix` and
  `/persist` are btrfs subvolumes, and only SSH identity, root SSH state,
  `/etc/machine-id`, and minimal NixOS/systemd state are persisted.
- The generated root console password path is implemented for the next fresh
  install, but the currently running failed install does not have that password.

## Still Broken

- Fresh `nixos-anywhere` install completed bootloader installation and rebooted,
  but SSH did not return because the bad `/etc/ssh` persistence hid
  `sshd_config`. The config fix is local/focused-tested but not live-validated
  yet.

## Pending / Unknown

- Whether the next fresh install returns on SSH after the `/etc/ssh`
  persistence fix.
- Whether the automatic Hetzner CA/profile issuance guard passes once the
  validator returns over SSH.
- Public-WAN reachability, Nebula handshakes, DNS-over-overlay, nftables
  safety, and leak prevention after the next fresh install.

## Next Concrete Debugging Target

- Clean up the current failed validator, start a fresh full-lab loop, and
  verify SSH returns after NixOS install. If it still refuses, use `pw.txt` in
  Hetzner console and capture the next exact systemd/network failure.

## Boundary Notes

- The Hetzner host is disposable validation state. Public addresses, delegated
  prefixes, generated passwords, and provider facts belong in runtime/SOPS flow,
  not committed model source.
- Hetzner persistence should stay minimal. Persisting SSH identity and machine
  identity is useful; broad logs, generated runtime outputs, and local
  debugging residue should not become durable state by default.
