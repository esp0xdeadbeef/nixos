#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "usage: $0 <updater> <hostname> [shutdown-hook]" >&2
  exit 64
fi

updater="$1"
host="$2"
shutdown_hook="${3:-}"
test_dir="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export FAKE_NIX_HOST="$host"
export FAKE_NIX_IMAGE_BASE="$work/images"
export FAKE_NIX_LOG="$work/nix.log"
export NIXOS_SHELL_NIX_BIN="$test_dir/fake-nix"
export NIXOS_SHELL_NIX_STORE_BIN="$test_dir/fake-nix-store"
export NIXOS_SHELL_FLOCK_BIN="$(command -v flock)"
export NIXOS_SHELL_GLOBAL_UPDATE_LOCK="$work/global.lock"
export NIXOS_SHELL_UPDATE_GENERATION=generation-1

source_flake="$work/switch-source"
mkdir -p "$source_flake"
printf '%s\n' switch-flake >"$source_flake/flake.nix"
printf '%s\n' switch-lock >"$source_flake/flake.lock"
printf '%s\n' switch-source >"$source_flake/source-marker"
export NIXOS_SHELL_SOURCE_FLAKE="path:$source_flake"
export FAKE_NIX_EXPECT_UPDATED_LOCK=true

chmod +x "$NIXOS_SHELL_NIX_BIN" "$NIXOS_SHELL_NIX_STORE_BIN"

root_success="$work/root-success"
export NIXOS_SHELL_IMAGE_ROOT="$root_success"
export FAKE_NIX_MODE=success
"$updater" --force
success_image="$(readlink -f "$root_success/current")"
test -x "$success_image/bin/run-$host-vm"
sed -n '1p' "$FAKE_NIX_LOG" | grep -Eq \
  '^flake update --refresh --flake path:.*/root-success/\.flake-update\.'
sed -n '2p' "$FAKE_NIX_LOG" | grep -Eq \
  '^build path:.*/root-success/\.flake-update\..*#nixosConfigurations\.'
if grep -q 'github:esp0xdeadbeef/nixos' "$FAKE_NIX_LOG"; then
  echo "updater unexpectedly replaced the switch source with GitHub" >&2
  exit 1
fi
test "$(cat "$source_flake/flake.lock")" = switch-lock
test "$(cat "$source_flake/source-marker")" = switch-source
test -z "$(find "$root_success" -maxdepth 1 -name '.flake-update.*' -print -quit)"

export FAKE_NIX_MODE=fail
if "$updater" --force; then
  echo "failed update unexpectedly succeeded" >&2
  exit 1
fi
test "$(readlink -f "$root_success/current")" = "$success_image"

root_fallback="$work/root-fallback"
export NIXOS_SHELL_IMAGE_ROOT="$root_fallback"
export FAKE_NIX_MODE=fail-lock-update
export FAKE_NIX_EXPECT_UPDATED_LOCK=false
"$updater" --force
fallback_image="$(readlink -f "$root_fallback/current")"
test -x "$fallback_image/bin/run-$host-vm"
tail -n 1 "$FAKE_NIX_LOG" | grep -Fq \
  "build path:$source_flake#nixosConfigurations.$host.config.system.build.nixos-shell"

root_stale="$work/root-stale"
mkdir -p "$root_stale"
ln -s "$success_image" "$root_stale/current"
export NIXOS_SHELL_IMAGE_ROOT="$root_stale"
export FAKE_NIX_MODE=fail
before_attempts="$(wc -l <"$FAKE_NIX_LOG")"
if "$updater" --if-stale; then
  echo "stale failed update unexpectedly succeeded" >&2
  exit 1
fi
"$updater" --if-stale
after_attempts="$(wc -l <"$FAKE_NIX_LOG")"
test "$after_attempts" -eq "$((before_attempts + 1))"

root_serial_a="$work/root-serial-a"
root_serial_b="$work/root-serial-b"
export FAKE_NIX_MODE=success
export FAKE_NIX_EXPECT_UPDATED_LOCK=true
export FAKE_NIX_SLEEP=1
export FAKE_NIX_CRITICAL_DIR="$work/critical"
export FAKE_NIX_OVERLAP_FAILURE="$work/overlap"

NIXOS_SHELL_IMAGE_ROOT="$root_serial_a" "$updater" --force &
pid_a=$!
NIXOS_SHELL_IMAGE_ROOT="$root_serial_b" "$updater" --force &
pid_b=$!
wait "$pid_a"
wait "$pid_b"
test ! -e "$FAKE_NIX_OVERLAP_FAILURE"

root_non_blocking="$work/root-non-blocking"
export NIXOS_SHELL_IMAGE_ROOT="$root_non_blocking"
export FAKE_NIX_SLEEP=1
export FAKE_NIX_CRITICAL_DIR="$work/non-blocking-critical"

"$updater" --force &
pid_blocking=$!
for _ in $(seq 1 100); do
  if [ -d "$FAKE_NIX_CRITICAL_DIR" ]; then
    break
  fi
  sleep 0.01
done
test -d "$FAKE_NIX_CRITICAL_DIR"
"$updater" --force --non-blocking
kill -0 "$pid_blocking"
wait "$pid_blocking"
test ! -e "$FAKE_NIX_OVERLAP_FAILURE"

if [ -n "$shutdown_hook" ]; then
  root_shutdown="$work/root-shutdown"
  export NIXOS_SHELL_IMAGE_ROOT="$root_shutdown"
  export FAKE_NIX_MODE=success
  unset FAKE_NIX_SLEEP FAKE_NIX_CRITICAL_DIR FAKE_NIX_OVERLAP_FAILURE

  before_shutdown_attempts="$(wc -l <"$FAKE_NIX_LOG")"
  SERVICE_RESULT=exit-code "$shutdown_hook"
  after_shutdown_attempts="$(wc -l <"$FAKE_NIX_LOG")"
  test "$after_shutdown_attempts" -eq "$((before_shutdown_attempts + 2))"
  sed -n "$((before_shutdown_attempts + 1))p" "$FAKE_NIX_LOG" \
    | grep -q '^flake update --refresh --flake path:'
  sed -n "${after_shutdown_attempts}p" "$FAKE_NIX_LOG" \
    | grep -q '#nixosConfigurations\.'
  test -x "$(readlink -f "$root_shutdown/current")/bin/run-$host-vm"

  SERVICE_RESULT=success "$shutdown_hook"
  test "$(wc -l <"$FAKE_NIX_LOG")" -eq "$after_shutdown_attempts"
fi

printf '%s\n' "image updater tests passed for $host"
