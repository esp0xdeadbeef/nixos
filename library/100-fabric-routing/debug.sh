#!/usr/bin/env bash
set -euo pipefail

TMP_FILE="/tmp/decrypted-wan.json"
trap 'rm -f "$TMP_FILE"' EXIT

# Direct JSON output from sops
sops -d --output-type json ../../secrets/s-routers-public-ips.yaml > "$TMP_FILE"

for f in lib/debug/[0-9][0-9]-*.nix; do
  base="$(basename "$f")"
  echo "==> $base"
  SOPS_WAN_FILE="$TMP_FILE" \
    nix eval --impure --file "lib/debug/${base}" --json | jq
done

