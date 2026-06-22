#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

update_yaml_secrets() {
  local file

  for file in secrets/*.yaml; do
    [[ -f "$file" ]] || continue
    grep -q 'sops:' "$file" || continue

    printf 'updatekeys %s\n' "$file"
    sops updatekeys -y "$file"
  done
}

update_json_age_secrets() {
  local file

  for file in secrets/*.json.age; do
    [[ -f "$file" ]] || continue
    grep -q '"sops"' "$file" || continue

    printf 'updatekeys %s\n' "$file"
    sops updatekeys -y --input-type json "$file"
  done
}

update_yaml_secrets
update_json_age_secrets
