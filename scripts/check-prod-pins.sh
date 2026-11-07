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

# Mutable input sources defeat pinning entirely: a `path:` (or file/git+file)
# input follows the working tree, so a rebuild silently produces different
# artifacts with flake.lock unchanged -- the same failure mode as a derived image,
# and the reason the protected pins are rev-pinned in flake.nix URLs. Refuse to
# let one into the tree at all.
mutable=$(grep -nE 'url[[:space:]]*=[[:space:]]*"(path|file|git\+file):' "$repo_root/flake.nix" || true)
pathnodes=$(python3 - "$lock" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for name, node in d["nodes"].items():
    if name == "root":
        continue
    locked = node.get("locked") or {}
    if locked.get("type") == "path":
        print(f"{name}: path:{locked.get('path')}")
PY
)
if [ -n "$mutable" ] || [ -n "$pathnodes" ]; then
  echo "mutable (unpinnable) flake inputs are not allowed:" >&2
  [ -n "$mutable" ] && printf '%s\n' "$mutable" >&2
  [ -n "$pathnodes" ] && printf '%s\n' "$pathnodes" >&2
  echo >&2
  echo "A path:/file:/git+file: input follows the working tree, so builds change" >&2
  echo "with flake.lock untouched. Pin an exact commit or a rev-pinned URL instead." >&2
  exit 1
fi

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
