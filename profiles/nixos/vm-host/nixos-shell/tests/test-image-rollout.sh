#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <rollout-program> <hostname>" >&2
  exit 64
fi

rollout_script="$1"
host="$2"
test_dir="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fake_bin="$work/bin"
mkdir -p "$fake_bin"
ln -s "$test_dir/fake-systemctl" "$fake_bin/systemctl"
ln -s "$test_dir/fake-tmux" "$fake_bin/tmux"
ln -s "$test_dir/fake-nix-store" "$fake_bin/nix-store"

export PATH="$fake_bin:$PATH"
export FAKE_VM_HOST="$host"
export NIXOS_SHELL_IMAGE_ROOT="$work/images"
export NIXOS_SHELL_LOCK_ROOT="$work/locks"
export NIXOS_SHELL_TMUX_SOCKET="$work/router.tmux"
export NIXOS_SHELL_FLOCK_BIN="$(command -v flock)"
export NIXOS_SHELL_NIX_STORE_BIN="$fake_bin/nix-store"
export NIXOS_SHELL_SYSTEMCTL_BIN="$fake_bin/systemctl"
export NIXOS_SHELL_TMUX_BIN="$fake_bin/tmux"
export FAKE_SYSTEMCTL_LOG="$work/systemctl.log"

for image in old candidate; do
  mkdir -p "$NIXOS_SHELL_IMAGE_ROOT/$image/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' \
    >"$NIXOS_SHELL_IMAGE_ROOT/$image/bin/run-${host}-vm"
  chmod +x "$NIXOS_SHELL_IMAGE_ROOT/$image/bin/run-${host}-vm"
done

select_candidate() {
  ln -sfn "$NIXOS_SHELL_IMAGE_ROOT/old" \
    "$NIXOS_SHELL_IMAGE_ROOT/restart-previous"
  ln -sfn "$NIXOS_SHELL_IMAGE_ROOT/candidate" \
    "$NIXOS_SHELL_IMAGE_ROOT/current"
}

select_candidate
"$rollout_script"

test "$(cat "$FAKE_SYSTEMCTL_LOG")" = "restart ${host}-vm.service"
test ! -e "$NIXOS_SHELL_IMAGE_ROOT/restart-previous"
test "$(readlink -e "$NIXOS_SHELL_IMAGE_ROOT/current")" = \
  "$NIXOS_SHELL_IMAGE_ROOT/candidate"

: >"$FAKE_SYSTEMCTL_LOG"
select_candidate
export FAKE_SYSTEMCTL_FAIL_RESTART_ONCE=true
export FAKE_SYSTEMCTL_RESTART_STATE="$work/restart-failed-once"

if "$rollout_script"; then
  echo "failed candidate unexpectedly reported a successful rollout" >&2
  exit 1
fi

test "$(sed -n '1p' "$FAKE_SYSTEMCTL_LOG")" = "restart ${host}-vm.service"
test "$(sed -n '2p' "$FAKE_SYSTEMCTL_LOG")" = "restart ${host}-vm.service"
test "$(readlink -e "$NIXOS_SHELL_IMAGE_ROOT/current")" = \
  "$NIXOS_SHELL_IMAGE_ROOT/old"
test ! -e "$NIXOS_SHELL_IMAGE_ROOT/restart-previous"

unset FAKE_SYSTEMCTL_FAIL_RESTART_ONCE
: >"$FAKE_SYSTEMCTL_LOG"
select_candidate
export FAKE_TMUX_FAIL_IMAGE="$NIXOS_SHELL_IMAGE_ROOT/candidate"
export NIXOS_SHELL_ROLLOUT_ATTEMPTS=1

if "$rollout_script"; then
  echo "candidate without a tmux pane unexpectedly reported a successful rollout" >&2
  exit 1
fi

test "$(sed -n '1p' "$FAKE_SYSTEMCTL_LOG")" = "restart ${host}-vm.service"
test "$(sed -n '2p' "$FAKE_SYSTEMCTL_LOG")" = "restart ${host}-vm.service"
test "$(readlink -e "$NIXOS_SHELL_IMAGE_ROOT/current")" = \
  "$NIXOS_SHELL_IMAGE_ROOT/old"
test ! -e "$NIXOS_SHELL_IMAGE_ROOT/restart-previous"

unset FAKE_TMUX_FAIL_IMAGE NIXOS_SHELL_ROLLOUT_ATTEMPTS
: >"$FAKE_SYSTEMCTL_LOG"
select_candidate
export FAKE_VM_INACTIVE=true

"$rollout_script"

test ! -s "$FAKE_SYSTEMCTL_LOG"
test "$(readlink -e "$NIXOS_SHELL_IMAGE_ROOT/current")" = \
  "$NIXOS_SHELL_IMAGE_ROOT/candidate"
test ! -e "$NIXOS_SHELL_IMAGE_ROOT/restart-previous"

printf '%s\n' "${host} image rollout tests passed"
