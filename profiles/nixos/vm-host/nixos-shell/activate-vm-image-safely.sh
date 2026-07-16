#!/usr/bin/env bash
set -euo pipefail

readonly host="${NIXOS_SHELL_HOST:?NIXOS_SHELL_HOST must be set}"
readonly image_root="${NIXOS_SHELL_IMAGE_ROOT:-/persist/nixos-shell-images/${host}}"
readonly current_link="${image_root}/current"
readonly previous_link="${image_root}/restart-previous"
readonly lock_root="${NIXOS_SHELL_LOCK_ROOT:-/run/lock/nixos-shell}"
readonly tmux_socket="${NIXOS_SHELL_TMUX_SOCKET:-/run/nixos-shell/${host}.tmux}"
readonly service="${NIXOS_SHELL_VM_SERVICE:-${host}-vm.service}"
readonly flock_bin="${NIXOS_SHELL_FLOCK_BIN:-flock}"
readonly nix_store_bin="${NIXOS_SHELL_NIX_STORE_BIN:-nix-store}"
readonly systemctl_bin="${NIXOS_SHELL_SYSTEMCTL_BIN:-systemctl}"
readonly tmux_bin="${NIXOS_SHELL_TMUX_BIN:-tmux}"
readonly rollout_attempts="${NIXOS_SHELL_ROLLOUT_ATTEMPTS:-90}"

mkdir -p "${image_root}" "${lock_root}"
exec 9>"${lock_root}/${host}-restart.lock"
if ! "${flock_bin}" -n 9; then
  echo "another ${host} image activation is already running" >&2
  exit 75
fi

candidate="$(readlink -e "${current_link}" 2>/dev/null || true)"
previous_image="$(readlink -e "${previous_link}" 2>/dev/null || true)"
candidate_runner="${candidate}/bin/run-${host}-vm"

if [[ -z "${candidate}" || ! -x "${candidate_runner}" ]]; then
  echo "${host}: no usable candidate runner at ${candidate_runner}" >&2
  exit 1
fi

running_image() {
  if ! "${tmux_bin}" -S "${tmux_socket}" has-session -t vm 2>/dev/null; then
    return 1
  fi

  "${tmux_bin}" -S "${tmux_socket}" \
    display-message -p -t vm '#{pane_start_command}'
}

wait_for_image() {
  local image="$1"
  local pane_command

  for _ in $(seq 1 "${rollout_attempts}"); do
    pane_command="$(running_image 2>/dev/null || true)"
    if [[ "${pane_command}" == *"${image}"* ]]; then
      return 0
    fi
    sleep 1
  done

  return 1
}

if ! "${systemctl_bin}" is-active --quiet "${service}"; then
  rm -f "${previous_link}"
  echo "${host}: VM is stopped; the candidate will be used on its next start"
  exit 0
fi

system_state="$("${systemctl_bin}" is-system-running 2>/dev/null || true)"
if [[ "${system_state}" == stopping ]]; then
  rm -f "${previous_link}"
  echo "${host}: host is stopping; the candidate will be used after boot"
  exit 0
fi

if [[ -z "${previous_image}" ]]; then
  pane_command="$(running_image 2>/dev/null || true)"
  if [[ "${pane_command}" == *"${candidate}"* ]]; then
    echo "${host}: candidate is already running: ${candidate}"
    exit 0
  fi

  echo "${host}: refusing to restart without a pinned previous image" >&2
  exit 1
fi

if [[ "${previous_image}" == "${candidate}" ]]; then
  rm -f "${previous_link}"
  echo "${host}: built image is already current: ${candidate}"
  exit 0
fi

previous_runner="${previous_image}/bin/run-${host}-vm"
if [[ ! -x "${previous_runner}" ]]; then
  echo "${host}: previous image has no usable runner: ${previous_runner}" >&2
  exit 1
fi

rollback() {
  "${nix_store_bin}" \
    --add-root "${current_link}" \
    --indirect \
    --realise "${previous_image}" >/dev/null

  if ! "${systemctl_bin}" restart "${service}"; then
    echo "${host}: rollback restart failed; ${previous_link} remains pinned" >&2
    return 1
  fi

  if ! wait_for_image "${previous_image}"; then
    echo "${host}: rollback VM did not expose its tmux pane; ${previous_link} remains pinned" >&2
    return 1
  fi

  rm -f "${previous_link}"
  echo "${host}: rolled back to ${previous_image}" >&2
}

if ! "${systemctl_bin}" restart "${service}"; then
  echo "${host}: candidate restart failed; restoring the previous image" >&2
  rollback || true
  exit 1
fi

if wait_for_image "${candidate}"; then
  rm -f "${previous_link}"
  echo "${host}: running the built image ${candidate}"
  exit 0
fi

echo "${host}: candidate did not expose its tmux pane; restoring the previous image" >&2
rollback || true
exit 1
