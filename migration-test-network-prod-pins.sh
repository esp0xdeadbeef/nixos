#!/usr/bin/env bash

set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
profile_path="${repo_root}/nixos/virtual-machine/nixos-shell-vm/s-router-prod"

modules=(
  "vlan2-reservation-dns.nix"
  "ipv6.nix"
  "dns-core-path-route-override.nix"
  "vlan2-management-override.nix"
  "nebula-ingress-path-route-override.nix"
  "vlan3-dns-authority-override.nix"
  "vlan2-ipv6-path-mtu-override.nix"
)

eval_without_module() {
  local module_name="$1"
  local result

  if ! result="$(
    nix eval --impure --raw --expr "
      let
        flake = builtins.getFlake \"path:${repo_root}\";
        profile = flake.outPath + \"/nixos/virtual-machine/nixos-shell-vm/s-router-prod\";
        candidate = flake.nixosConfigurations.s-router-prod.extendModules {
          modules = [ {
            disabledModules = [ (profile + \"/${module_name}\") ];
          } ];
        };
        attempt = builtins.tryEval candidate.config.system.build.toplevel.drvPath;
      in
      if attempt.success then \"PASS\" else \"FAIL\"
    "
  )"; then
    printf '%s\tEVAL_ERROR\n' "${module_name}"
    return 1
  fi

  printf '%s\t%s\n' "${module_name}" "${result}"
  [[ "${result}" == "PASS" ]]
}

pids=()
for module_name in "${modules[@]}"; do
  if [[ ! -f "${profile_path}/${module_name}" ]]; then
    printf '%s\tMISSING\n' "${module_name}" >&2
    exit 1
  fi

  eval_without_module "${module_name}" &
  pids+=("$!")
done

exit_code=0
for pid in "${pids[@]}"; do
  if ! wait "${pid}"; then
    exit_code=1
  fi
done

exit "${exit_code}"
