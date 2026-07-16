#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <restart-program> <hostname>" >&2
  exit 64
fi

restart_script="$1"
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

mkdir -p "$NIXOS_SHELL_IMAGE_ROOT/old/bin"
printf '#!/usr/bin/env bash\nexit 0\n' \
  >"$NIXOS_SHELL_IMAGE_ROOT/old/bin/run-${host}-vm"
chmod +x "$NIXOS_SHELL_IMAGE_ROOT/old/bin/run-${host}-vm"
ln -s "$NIXOS_SHELL_IMAGE_ROOT/old" "$NIXOS_SHELL_IMAGE_ROOT/current"

"$restart_script"

test "$(sed -n '1p' "$FAKE_SYSTEMCTL_LOG")" = "start ${host}-image.service"
test "$(sed -n '2p' "$FAKE_SYSTEMCTL_LOG")" = "restart ${host}-vm.service"
test ! -e "$NIXOS_SHELL_IMAGE_ROOT/restart-previous"
test "$(readlink -e "$NIXOS_SHELL_IMAGE_ROOT/current")" = \
  "$NIXOS_SHELL_IMAGE_ROOT/fake-candidate"

: >"$FAKE_SYSTEMCTL_LOG"
ln -sfn "$NIXOS_SHELL_IMAGE_ROOT/old" "$NIXOS_SHELL_IMAGE_ROOT/current"
export FAKE_SYSTEMCTL_FAIL_IMAGE=true

if "$restart_script"; then
  echo "failed image update unexpectedly restarted ${host}" >&2
  exit 1
fi

test "$(cat "$FAKE_SYSTEMCTL_LOG")" = "start ${host}-image.service"
test "$(readlink -e "$NIXOS_SHELL_IMAGE_ROOT/current")" = \
  "$NIXOS_SHELL_IMAGE_ROOT/old"

printf '%s\n' "${host} restart ordering tests passed"
