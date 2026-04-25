#!/usr/bin/env bash
set -euo pipefail

cd /home/deadbeef/github/nixos

unseal_script="$(
  nix eval --extra-experimental-features dynamic-derivations --raw \
    .#nixosConfigurations.s-router-test.config.systemd.services.nebula-ca-unseal.script
)"

bootstrap_script="$(
  nix eval --extra-experimental-features dynamic-derivations --raw \
    .#nixosConfigurations.s-router-test.config.systemd.services.nebula-profile-bootstrap.script
)"

path_exists="$(
  nix eval --extra-experimental-features dynamic-derivations --raw \
    .#nixosConfigurations.s-router-test.config.systemd.paths.nebula-profile-bootstrap.pathConfig.PathExists
)"

for pattern in \
  '/run/keys/nebula-ca-passphrase' \
  'ca.key.enc' \
  'openssl enc -aes-256-cbc -pbkdf2 -salt' \
  'openssl enc -d -aes-256-cbc -pbkdf2'
do
  if ! grep -Fq "$pattern" <<<"$unseal_script"; then
    echo "missing expected nebula-ca-unseal pattern: $pattern" >&2
    exit 1
  fi
done

for pattern in \
  '/run/nebula-runtime/unsealed/ca.key' \
  'missing unlocked CA material; run nebula-ca-unseal first'
do
  if ! grep -Fq "$pattern" <<<"$bootstrap_script"; then
    echo "missing expected nebula-profile-bootstrap pattern: $pattern" >&2
    exit 1
  fi
done

if [[ "$path_exists" != "/run/nebula-runtime/unsealed/ca.key" ]]; then
  echo "unexpected nebula-profile-bootstrap path trigger: $path_exists" >&2
  exit 1
fi

echo "nebula CA unseal flow renders as expected"
