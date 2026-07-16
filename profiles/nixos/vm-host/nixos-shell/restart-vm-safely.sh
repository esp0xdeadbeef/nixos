#!/usr/bin/env bash
set -euo pipefail

readonly host="${NIXOS_SHELL_HOST:?NIXOS_SHELL_HOST must be set}"
readonly image_root="${NIXOS_SHELL_IMAGE_ROOT:-/persist/nixos-shell-images/${host}}"
readonly current_link="${image_root}/current"
readonly previous_link="${image_root}/restart-previous"
readonly lock_root="${NIXOS_SHELL_LOCK_ROOT:-/run/lock/nixos-shell}"
readonly tmux_socket="${NIXOS_SHELL_TMUX_SOCKET:-/run/nixos-shell/${host}.tmux}"
readonly service="${NIXOS_SHELL_VM_SERVICE:-${host}-vm.service}"
readonly image_service="${NIXOS_SHELL_IMAGE_SERVICE:-${host}-image.service}"
readonly image_service_rolls_out="${NIXOS_SHELL_IMAGE_SERVICE_ROLLOUT:-false}"
readonly rollout_service="${NIXOS_SHELL_ROLLOUT_SERVICE:-${host}-rollout.service}"
readonly flock_bin="${NIXOS_SHELL_FLOCK_BIN:-flock}"
readonly nix_store_bin="${NIXOS_SHELL_NIX_STORE_BIN:-nix-store}"
readonly systemctl_bin="${NIXOS_SHELL_SYSTEMCTL_BIN:-systemctl}"
readonly tmux_bin="${NIXOS_SHELL_TMUX_BIN:-tmux}"

if [[ "${image_service_rolls_out}" == true ]]; then
  if ! "${systemctl_bin}" start "${image_service}"; then
    echo "${host}: image update failed; the running VM is untouched" >&2
    exit 1
  fi

  for _ in $(seq 1 300); do
    if "${systemctl_bin}" is-failed --quiet "${rollout_service}"; then
      echo "${host}: image rollout failed or was rolled back" >&2
      exit 1
    fi

    candidate="$(readlink -e "${current_link}" 2>/dev/null || true)"
    if [[ ! -e "${previous_link}" ]]; then
      if ! "${systemctl_bin}" is-active --quiet "${service}"; then
        echo "${host}: cached the built image ${candidate}; the VM remains stopped"
        exit 0
      fi

      pane_command="$(
        "${tmux_bin}" -S "${tmux_socket}" \
          display-message -p -t vm '#{pane_start_command}' 2>/dev/null || true
      )"
      if [[ -n "${candidate}" && "${pane_command}" == *"${candidate}"* ]]; then
        if [[ -t 0 && -t 1 ]]; then
          exec env TMUX= "${tmux_bin}" -S "${tmux_socket}" attach -t vm
        fi

        echo "${host}: running the built image ${candidate}"
        exit 0
      fi
    fi

    sleep 1
  done

  echo "${host}: timed out waiting for the image rollout" >&2
  exit 1
fi

mkdir -p "${image_root}" "${lock_root}"
exec 9>"${lock_root}/${host}-restart.lock"
if ! "${flock_bin}" -n 9; then
  echo "another ${host} build/restart is already running" >&2
  exit 75
fi

old_image="$(readlink -e "${current_link}" 2>/dev/null || true)"
if [[ -n "${old_image}" ]]; then
  "${nix_store_bin}" \
    --add-root "${previous_link}" \
    --indirect \
    --realise "${old_image}" >/dev/null
fi

if ! "${systemctl_bin}" start "${image_service}"; then
  echo "${host}: image update failed; the running VM is untouched" >&2
  exit 1
fi

candidate="$(readlink -e "${current_link}" 2>/dev/null || true)"
candidate_runner="${candidate}/bin/run-${host}-vm"
if [[ -z "${candidate}" || ! -x "${candidate_runner}" ]]; then
  echo "${host}: image service produced no usable runner: ${candidate_runner}" >&2
  exit 1
fi

if ! "${systemctl_bin}" restart "${service}"; then
  echo "${host}: candidate is cached, but the VM restart failed" >&2
  echo "${host}: previous image remains pinned at ${previous_link}" >&2
  exit 1
fi

for _ in $(seq 1 90); do
  if "${tmux_bin}" -S "${tmux_socket}" has-session -t vm 2>/dev/null; then
    pane_command="$("${tmux_bin}" -S "${tmux_socket}" display-message -p -t vm '#{pane_start_command}')"
    if [[ "${pane_command}" == *"${candidate}"* ]]; then
      rm -f "${previous_link}"
      echo "${host}: running the built image ${candidate}"
      if [[ -t 0 && -t 1 ]]; then
        exec env TMUX= "${tmux_bin}" -S "${tmux_socket}" attach -t vm
      fi
      exit 0
    fi
  fi
  sleep 1
done

echo "${host}: restart did not expose a tmux pane for ${candidate}" >&2
echo "${host}: previous image remains pinned at ${previous_link}" >&2
exit 1
