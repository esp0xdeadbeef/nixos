#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <image-service-script> <rollout-program> <hostname>" >&2
  exit 64
fi

image_service_script="$1"
rollout_script="$2"
host="$3"
test_dir="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fake_bin="$work/bin"
mkdir -p "$fake_bin"
ln -s "$test_dir/fake-systemctl" "$fake_bin/systemctl"
ln -s "$test_dir/fake-tmux" "$fake_bin/tmux"
ln -s "$test_dir/fake-nix" "$fake_bin/nix"
ln -s "$test_dir/fake-nix-store" "$fake_bin/nix-store"

export PATH="$fake_bin:$PATH"
export FAKE_VM_HOST="$host"
export FAKE_NIX_HOST="$host"
export FAKE_NIX_IMAGE_BASE="$work/built-images"
export FAKE_NIX_LOG="$work/nix.log"
export FAKE_NIX_MODE=success
export FAKE_ROLLOUT_PROGRAM="$rollout_script"
export FAKE_ROLLOUT_FAILED_STATE="$work/rollout-failed"
export FAKE_SYSTEMCTL_LOG="$work/systemctl.log"
export NIXOS_SHELL_FLOCK_BIN="$(command -v flock)"
export NIXOS_SHELL_GLOBAL_UPDATE_LOCK="$work/global.lock"
export NIXOS_SHELL_IMAGE_ROOT="$work/images"
export NIXOS_SHELL_LOCK_ROOT="$work/locks"
export NIXOS_SHELL_NIX_BIN="$fake_bin/nix"
export NIXOS_SHELL_NIX_STORE_BIN="$fake_bin/nix-store"
export NIXOS_SHELL_PRIMARY_FLAKE=good:primary
export NIXOS_SHELL_FALLBACK_FLAKE=good:fallback
export NIXOS_SHELL_PRIMARY_REFRESH=true
export NIXOS_SHELL_SYSTEMCTL_BIN="$fake_bin/systemctl"
export NIXOS_SHELL_TMUX_BIN="$fake_bin/tmux"
export NIXOS_SHELL_TMUX_SOCKET="$work/router.tmux"
export NIXOS_SHELL_UPDATE_GENERATION=generation-flow-test

old_image="$work/old"
mkdir -p "$old_image/bin" "$NIXOS_SHELL_IMAGE_ROOT"
printf '#!/usr/bin/env bash\nexit 0\n' >"$old_image/bin/run-${host}-vm"
chmod +x "$old_image/bin/run-${host}-vm"
ln -s "$old_image" "$NIXOS_SHELL_IMAGE_ROOT/current"

"$image_service_script"

candidate="$(readlink -e "$NIXOS_SHELL_IMAGE_ROOT/current")"
test "$candidate" != "$old_image"
test -x "$candidate/bin/run-${host}-vm"
test "$(sed -n '1p' "$FAKE_SYSTEMCTL_LOG")" = \
  "start --no-block ${host}-rollout.service"
test "$(sed -n '2p' "$FAKE_SYSTEMCTL_LOG")" = \
  "restart ${host}-vm.service"
test ! -e "$NIXOS_SHELL_IMAGE_ROOT/restart-previous"
test ! -e "$FAKE_ROLLOUT_FAILED_STATE"

: >"$FAKE_SYSTEMCTL_LOG"
ln -sfn "$old_image" "$NIXOS_SHELL_IMAGE_ROOT/current"
export FAKE_NIX_MODE=fail

if "$image_service_script"; then
  echo "failed build unexpectedly scheduled a rollout" >&2
  exit 1
fi

test ! -s "$FAKE_SYSTEMCTL_LOG"
test "$(readlink -e "$NIXOS_SHELL_IMAGE_ROOT/current")" = "$old_image"
test ! -e "$NIXOS_SHELL_IMAGE_ROOT/restart-previous"

printf '%s\n' "${host} image service rollout flow tests passed"
