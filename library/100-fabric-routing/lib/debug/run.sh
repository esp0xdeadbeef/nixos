#!/usr/bin/env bash
set -euo pipefail

file="${1:-40-node.nix}"
shift || true

nix eval --file "lib/debug/${file}" "$@" --json | jq

