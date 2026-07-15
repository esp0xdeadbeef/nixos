#!/usr/bin/env bash
set -euo pipefail

readonly host="s-router-prod"
readonly flake_ref="${S_ROUTER_PROD_FLAKE:?S_ROUTER_PROD_FLAKE must point at the store-pinned flake}"
readonly image_root="${S_ROUTER_PROD_IMAGE_ROOT:-/persist/nixos-shell-images/${host}}"
readonly current_link="${image_root}/current"
readonly candidate_link="${image_root}/candidate"
readonly previous_link="${image_root}/restart-previous"
readonly lock_root="${S_ROUTER_PROD_LOCK_ROOT:-/run/lock/nixos-shell}"
readonly tmux_socket="${S_ROUTER_PROD_TMUX_SOCKET:-/run/nixos-shell/${host}.tmux}"
readonly service="${S_ROUTER_PROD_SERVICE:-${host}-vm.service}"

case "${flake_ref}" in
  path:/nix/store/*)
    ;;
  *)
    echo "refusing non-store s-router-prod flake: ${flake_ref}" >&2
    exit 64
    ;;
esac

mkdir -p "${image_root}" "${lock_root}"
exec 9>"${lock_root}/${host}-restart.lock"
if ! flock -n 9; then
  echo "another ${host} build/restart is already running" >&2
  exit 75
fi

if ! nix build \
  "${flake_ref}#nixosConfigurations.${host}.config.system.build.nixos-shell" \
  --out-link "${candidate_link}"; then
  echo "${host}: build failed; the running VM and current image are untouched" >&2
  exit 1
fi

candidate="$(readlink -e "${candidate_link}")"
candidate_runner="${candidate}/bin/run-${host}-vm"
if [[ ! -x "${candidate_runner}" ]]; then
  echo "${host}: candidate has no executable runner: ${candidate_runner}" >&2
  exit 1
fi

old_image="$(readlink -e "${current_link}" 2>/dev/null || true)"
if [[ -n "${old_image}" ]]; then
  nix-store \
    --add-root "${previous_link}" \
    --indirect \
    --realise "${old_image}" >/dev/null
fi

nix-store \
  --add-root "${current_link}" \
  --indirect \
  --realise "${candidate}" >/dev/null

# Adopt an older manually started tmux/QEMU instance before restarting it. This
# makes systemd the sole supervisor without starting a second VM.
systemctl start "${service}"
if ! systemctl restart "${service}"; then
  echo "${host}: candidate is cached, but the VM restart failed" >&2
  echo "${host}: previous image remains pinned at ${previous_link}" >&2
  exit 1
fi

for _ in $(seq 1 90); do
  if tmux -S "${tmux_socket}" has-session -t vm 2>/dev/null; then
    pane_command="$(tmux -S "${tmux_socket}" display-message -p -t vm '#{pane_start_command}')"
    if [[ "${pane_command}" == *"${candidate}"* ]]; then
      rm -f "${previous_link}"
      echo "${host}: running the built image ${candidate}"
      if [[ -t 0 && -t 1 ]]; then
        exec env TMUX= tmux -S "${tmux_socket}" attach -t vm
      fi
      exit 0
    fi
  fi
  sleep 1
done

echo "${host}: restart did not expose a tmux pane for ${candidate}" >&2
echo "${host}: previous image remains pinned at ${previous_link}" >&2
exit 1
