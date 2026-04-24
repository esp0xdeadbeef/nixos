#!/usr/bin/env bash
set -euo pipefail

cd /home/deadbeef/github/nixos

script_text="$(
  nix eval --raw \
    .#nixosConfigurations.s-router-test.config.systemd.services.nebula-profile-bootstrap.script
)"

required_patterns=(
  'unsafe_routes:'
  'local_cidr: 0.0.0.0/1'
  'local_cidr: 128.0.0.0/1'
  'local_cidr: ::/1'
  'local_cidr: 8000::/1'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" <<<"$script_text"; then
    echo "missing expected nebula bootstrap pattern: $pattern" >&2
    exit 1
  fi
done

echo "nebula unsafe-route firewall rendering looks present"
