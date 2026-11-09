#!/usr/bin/env bash
# Refuse to commit or push changes to the protected production surfaces.
#
# AGENTS.md states the rule ("Protected paths: prod and legacy-prod (absolute
# rule)") but for a long time nothing enforced it: pre-commit only guarded the
# *flake.lock pins* (scripts/check-prod-pins.sh), and no hook or CI job looked at
# the content of the protected paths at all. A content edit under
# prod-network/prod/ therefore landed silently. This script closes that gap.
#
# Protected surfaces, taken from the AGENTS.md list "at minimum":
#   - prod-network/prod/
#   - prod-network/current/
#   - any *-prod / *-legacy-prod flake input and pin (flake.nix, flake.lock)
#   - the s-router-prod / s-router-legacy-prod / s-router-prod-* /
#     s-router-legacy-prod-* host configs and their secrets
#
# Two separate permissions are required by AGENTS.md -- one to edit, one to
# push -- so the approval token names the permission it grants and the exact
# files it covers:
#
#   PROD_PATHS_APPROVED="edit:prod-network/prod/intent.nix prod-network/prod/inventory-cobalt.nix" \
#     git commit ...
#
#   PROD_PATHS_APPROVED="push" git push ...
#
# The edit permission must name every protected file in the commit; a general
# approval, an earlier approval, or another file's approval is not permission.
#
# Usage:
#   scripts/check-prod-paths.sh --staged     # pre-commit: staged changes
#   scripts/check-prod-paths.sh --revs <sha>...  # pre-push: commits being pushed
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Is this path one of the protected production surfaces?
is_protected() {
  local path=$1
  case "$path" in
    # The two whole-directory surfaces.
    prod-network/prod/* | prod-network/current/*) return 0 ;;
    # Host configs and their secrets for the prod / legacy-prod routers.
    nixos/*/s-router-prod | nixos/*/s-router-prod/*) return 0 ;;
    nixos/*/s-router-prod-* | nixos/*/s-router-prod-*/*) return 0 ;;
    nixos/*/s-router-legacy-prod | nixos/*/s-router-legacy-prod/*) return 0 ;;
    nixos/*/s-router-legacy-prod-* | nixos/*/s-router-legacy-prod-*/*) return 0 ;;
    secrets/s-router-prod* | secrets/s-router-legacy-prod*) return 0 ;;
    # The flake inputs and pins themselves.
    flake.nix | flake.lock) return 0 ;;
  esac
  return 1
}

# flake.nix/flake.lock are only protected for *-prod / *-legacy-prod changes;
# an unrelated edit elsewhere in them is not this gate's business.
flake_only_prod_change() {
  local rev=$1
  local diff
  diff=$(git -C "$repo_root" show --unified=0 --format= "$rev" -- flake.nix flake.lock 2>/dev/null || true)
  [ -z "$diff" ] && return 1
  # Protected iff the changed lines mention a prod/legacy-prod input or pin.
  printf '%s\n' "$diff" | grep -qE '^[+-].*(prod|legacy-prod)' && return 0
  return 1
}

approved_files=()
approve_all_push=0
case "${PROD_PATHS_APPROVED:-}" in
  "") ;;
  push) approve_all_push=1 ;;
  edit:*) read -r -a approved_files <<<"${PROD_PATHS_APPROVED#edit:}" ;;
  *)
    echo "PROD_PATHS_APPROVED must be 'push' or 'edit:<file> [<file>...]'" >&2
    exit 1
    ;;
esac

is_approved_file() {
  local candidate=$1 f
  for f in "${approved_files[@]}"; do
    [ "$f" = "$candidate" ] && return 0
  done
  return 1
}

report() {
  local mode=$1
  shift
  local -a offending=("$@")
  echo >&2
  echo "protected production paths ($mode):" >&2
  printf '  %s\n' "${offending[@]}" >&2
  echo >&2
  echo "AGENTS.md treats these as read-only without explicit, current," >&2
  echo "per-session permission that names the exact files. Two separate" >&2
  echo "permissions exist and both are required:" >&2
  echo "  1. permission to EDIT the protected files" >&2
  echo "  2. permission to PUSH the resulting commits" >&2
  echo >&2
  if [ "$mode" = "commit" ]; then
    echo "Grant the edit permission for exactly these files to commit them:" >&2
    echo "  PROD_PATHS_APPROVED=\"edit:$*\" git commit ..." >&2
  else
    echo "Grant the push permission to push them:" >&2
    echo "  PROD_PATHS_APPROVED=push git push ..." >&2
  fi
  echo >&2
  echo "Do not 'restore', 'check out', or 'clean' these paths as a side effect" >&2
  echo "of another task. When in doubt, stop and ask." >&2
  exit 1
}

mode=${1:-}
shift || true

case "$mode" in
  --staged)
    mapfile -t paths < <(git -C "$repo_root" diff --cached --name-only --diff-filter=ACMRD)
    offending=()
    for path in "${paths[@]}"; do
      if is_protected "$path"; then
        if [ "$approve_all_push" = "1" ]; then
          continue
        fi
        # flake.nix/flake.lock only trip the gate for prod-pin changes.
        if [ "$path" = "flake.nix" ] || [ "$path" = "flake.lock" ]; then
          flake_only_prod_change "$(git -C "$repo_root" write-tree)" || continue
        else
          is_approved_file "$path" && continue
        fi
        offending+=("$path")
      fi
    done
    [ ${#offending[@]} -eq 0 ] && exit 0
    report commit "${offending[@]}"
    ;;

  --revs)
    [ ${#} -eq 0 ] && exit 0
    [ "$approve_all_push" = "1" ] && exit 0
    offending=()
    for rev in "$@"; do
      while IFS= read -r path; do
        [ -n "$path" ] || continue
        is_protected "$path" || continue
        if [ "$path" = "flake.nix" ] || [ "$path" = "flake.lock" ]; then
          flake_only_prod_change "$rev" || continue
        fi
        offending+=("$rev:$path")
      done < <(git -C "$repo_root" show --name-only --format= "$rev" 2>/dev/null || true)
    done
    [ ${#offending[@]} -eq 0 ] && exit 0
    report push "${offending[@]}"
    ;;

  *)
    echo "usage: $0 --staged | --revs <rev>..." >&2
    exit 2
    ;;
esac
