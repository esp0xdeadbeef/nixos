#!/usr/bin/env bash
set -euo pipefail

for f in lib/debug/[0-9][0-9]-*.nix; do
  base="$(basename "$f")"
  echo "==> $base"
  ./lib/debug/run.sh "$base"
done

