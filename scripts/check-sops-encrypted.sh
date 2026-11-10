#!/usr/bin/env bash
# Refuse to commit a secrets file that is not actually SOPS-encrypted.
#
# Decryption only works if the file was encrypted in the first place, and the
# failure mode is silent: a plaintext value sits in the tree looking like data,
# decrypts "fine" because there is nothing to decrypt, and the secret is already
# public. That happened here with a resolver list written in clear.
#
# This checks the committed shape of every secrets file:
#   - a SOPS metadata block must be present;
#   - at least one value must be ciphertext;
#   - no PEM private key and no bare address may appear as a plaintext value.
#
# A file that legitimately has no encrypted value (an empty placeholder) must say
# so with `sops.unencrypted_suffix`, so the exception is visible in review
# instead of being inferred from a missing match.
#
# Usage:
#   scripts/check-sops-encrypted.sh            # every tracked secrets file
#   scripts/check-sops-encrypted.sh --staged   # the staged content only
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

mode=${1:-}
case "$mode" in
  "" | --staged) ;;
  *)
    echo "usage: $0 [--staged]" >&2
    exit 2
    ;;
esac

# Read the content under test: staged blob when asked, working tree otherwise.
content_of() {
  local path=$1
  if [ "$mode" = "--staged" ]; then
    git show ":$path" 2>/dev/null || return 1
  else
    cat "$path"
  fi
}

if [ "$mode" = "--staged" ]; then
  mapfile -t files < <(git diff --cached --name-only --diff-filter=ACMR -- 'secrets/**')
else
  mapfile -t files < <(git ls-files -- 'secrets/**')
fi

failures=0
checked=0

for path in "${files[@]}"; do
  case "$path" in
    *.yaml | *.yml) ;;
    *) continue ;;
  esac
  # The SOPS configuration file is not itself a secret.
  case "$path" in
    */.sops.yaml | .sops.yaml) continue ;;
  esac

  content=$(content_of "$path") || continue
  checked=$((checked + 1))

  if ! printf '%s\n' "$content" | grep -qE '^sops:|^[[:space:]]*"sops"[[:space:]]*:'; then
    echo "NOT ENCRYPTED: ${path}: no sops metadata block" >&2
    failures=$((failures + 1))
    continue
  fi

  if ! printf '%s\n' "$content" | grep -qE 'ENC\[|^[[:space:]]+"?enc"?[[:space:]]*:'; then
    # An intentionally value-less file must declare it, so the exemption is
    # visible in the diff rather than implied.
    if ! printf '%s\n' "$content" | grep -qE 'unencrypted_suffix|unencrypted_regex'; then
      echo "NOT ENCRYPTED: ${path}: no ciphertext and no declared unencrypted suffix" >&2
      failures=$((failures + 1))
      continue
    fi
  fi

  if printf '%s\n' "$content" | grep -qE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----'; then
    echo "PLAINTEXT KEY: ${path}: PEM private key in clear" >&2
    failures=$((failures + 1))
    continue
  fi

  if printf '%s\n' "$content" | grep -qE '^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*("?)([0-9]{1,3}\.){3}[0-9]{1,3}\1[[:space:]]*$'; then
    echo "PLAINTEXT ADDRESS: ${path}: bare address as a value" >&2
    failures=$((failures + 1))
    continue
  fi
done

if [ "$failures" -gt 0 ]; then
  echo >&2
  echo "${failures} secrets file(s) are not encrypted as required." >&2
  echo "Encrypt with: sops --encrypt --in-place <file>" >&2
  exit 1
fi

echo "sops encryption check passed (${checked} secrets file(s))"
