#!/usr/bin/env bash
# Refuse to move a protected production pin without an explicit approval.
#
# The protected pins are the `*-prod` / `*-legacy-prod` flake inputs. They are
# ordinary entries in flake.lock, so a plain `nix flake update` -- including the
# nightly workflow in .github/workflows/flake-lock-update-main.yml -- will move
# them like any other input. That is unacceptable: the production and legacy
# production network shapes are the surfaces a live site runs on.
#
# Mechanism: ci/prod-pins.lock is a committed snapshot of those pins. Any change
# is a diff in this repo, and this check fails until the snapshot is regenerated
# in the same commit -- which makes the bump visible in review instead of
# arriving through an unattended job.
#
# Approve a real bump with:
#   PROD_PINS_APPROVED=1 scripts/check-prod-pins.sh --write   # then commit both
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
lock="$repo_root/flake.lock"
snapshot="$repo_root/ci/prod-pins.lock"

current=$(mktemp)
trap 'rm -f "$current"' EXIT

python3 - "$lock" > "$current" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
prod = {}
for name, node in d["nodes"].items():
    if name == "root" or "prod" not in name:
        continue
    locked = node.get("locked") or {}
    prod[name] = {
        "rev": locked.get("rev"),
        "narHash": locked.get("narHash"),
        "lastModified": locked.get("lastModified"),
    }
print(json.dumps(prod, indent=2, sort_keys=True))
PY

if [ "${1:-}" = "--write" ]; then
  [ "${PROD_PINS_APPROVED:-0}" = "1" ] || {
    echo "refusing to rewrite ci/prod-pins.lock: set PROD_PINS_APPROVED=1 to approve the bump" >&2
    exit 1
  }
  cp "$current" "$snapshot"
  echo "ci/prod-pins.lock updated; commit it together with flake.lock"
  exit 0
fi

if ! diff -u "$snapshot" "$current" > /tmp/prod-pins.diff 2>&1; then
  echo "protected production pins changed:" >&2
  sed -n '1,40p' /tmp/prod-pins.diff >&2
  echo >&2
  echo "The *-prod / *-legacy-prod pins must not move by accident. If this bump is" >&2
  echo "intended, approve it explicitly and commit the new snapshot:" >&2
  echo "  PROD_PINS_APPROVED=1 scripts/check-prod-pins.sh --write" >&2
  echo "  git add flake.lock ci/prod-pins.lock" >&2
  exit 1
fi

echo "protected production pins unchanged"
