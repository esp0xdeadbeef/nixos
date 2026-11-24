#!/usr/bin/env bash
# GAMP-SCOPE: process control; an agent's completion proof must name real work
#
# AN ESCAPE PROOF THAT A POINTER DOCUMENT SATISFIES IS NOT A PROOF.
#
# Measured 2026-11-24. A goal run landed six commits in three child repositories,
# every one of them a crash plus a seeded negative. The goal file lived in a
# scratch directory, and the harness resolved the "solution" commit relative to
# THAT directory, so the accepted proof was:
#
#     mkdir /tmp/handoff && git init && git add <the goal document> RESULT.md
#     git commit -m "record the result"
#
# `solution:` pointed at that commit. Nothing about it named, touched, or needed
# any of the six repositories the work was in. The same escape is available to a
# run that did nothing at all, which is what makes it theatre rather than a
# weak-but-honest check.
#
# This script is the missing check, stated as the handoff states it: the solution
# commit must touch a file the goal names, and it must not be a documentation-only
# commit. Two independent conditions, because each covers a case the other does
# not:
#
#   PROVENANCE   at least one path the commit changed is a path the goal text
#                names. A commit that touches nothing the goal asked for is not a
#                solution to that goal, however real it is.
#   SUBSTANCE    at least one changed path is not a document (.md/.rst/.txt).
#                This is what rejects `git init /tmp/x && commit a README`, and
#                it rejects a commit that only edits a goal note.
#
# Both conditions are necessary and neither is sufficient: a commit can touch a
# named file and still be wrong, and that is the reviewer's job, not this
# script's. What it removes is the class of proof that is satisfiable without
# doing the work.
#
# A third check, for the other half of the proof. `spec:` is normally defended by
# "run sha256sum yourself", which says nothing about whether the digest a result
# document quotes is the goal it actually answered. Measured this session: the
# digest moved twice while the run was in progress, so a record that quoted the
# first one looked verified and named a document nobody had any more.
#
#   DIGEST       a record that quotes a digest must quote the digest of the goal
#                file it is recorded against, or say that it is stale.
#
# Usage:
#   goal-escape-provenance.sh <goal-file> <commit> [<workspace-root>]
#   goal-escape-provenance.sh --check-digest <goal-file> <record-file>
#
# Exit: 0 the commit has provenance and substance; 1 it does not; 2 misuse.
#
# Evidence boundary: construction. Git plumbing plus a text scan of the goal.
set -euo pipefail

if [[ "${1:-}" == "--check-digest" ]]; then
  [[ $# -eq 3 ]] || {
    echo "usage: goal-escape-provenance.sh --check-digest <goal-file> <record-file>" >&2
    exit 2
  }
  goal_for_digest="$2"
  record_file="$3"
  [[ -f "${goal_for_digest}" ]] || {
    echo "FAIL GOAL-ESCAPE-PROVENANCE: no goal file at ${goal_for_digest}" >&2
    exit 2
  }
  [[ -f "${record_file}" ]] || {
    echo "FAIL GOAL-ESCAPE-PROVENANCE: no record file at ${record_file}" >&2
    exit 2
  }
  want_digest="$(cat "${goal_for_digest}" | sha256sum | cut -d' ' -f1)"
  # Any 64-hex digest in the record is a claim about a goal document.
  mapfile -t quoted < <(grep -oE '\b[0-9a-f]{64}\b' "${record_file}" | LC_ALL=C sort -u)
  if ((${#quoted[@]} == 0)); then
    echo "  note: ${record_file} quotes no digest, so there is nothing to compare" >&2
    exit 0
  fi
  found=0
  others=()
  for digest in "${quoted[@]}"; do
    if [[ "${digest}" == "${want_digest}" ]]; then
      found=1
    else
      others+=("${digest}")
    fi
  done

  # A record may legitimately quote several goals' digests -- one document, many
  # runs. So the question is not "is every quoted digest this goal's" but "does
  # this record quote THIS goal's digest at all". A record whose only digest is a
  # stale one is the failure this catches; extra digests are other documents and
  # are reported, not judged.
  if ((found == 1)); then
    echo "PASS DIGEST: ${record_file} quotes the digest of ${goal_for_digest} (${want_digest})"
    if ((${#others[@]} > 0)); then
      echo "  other digests in the record belong to other goal documents (not compared):"
      printf '    %s\n' "${others[@]}"
    fi
    exit 0
  fi

  {
    echo "FAIL DIGEST: ${record_file} quotes no digest of ${goal_for_digest}."
    echo "  goal now: ${want_digest}"
    printf '  quoted:   %s\n' "${quoted[@]}"
    echo "  A record whose only digest is a stale one claims verification against a"
    echo "  document that no longer exists. Recompute with:"
    echo "    cat ${goal_for_digest} | sha256sum"
  } >&2
  exit 1
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: goal-escape-provenance.sh <goal-file> <commit> [<workspace-root>]" >&2
  echo "       goal-escape-provenance.sh --check-digest <goal-file> <record-file>" >&2
  exit 2
fi

goal_file="$1"
commit="$2"
workspace_root="${3:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

[[ -f "${goal_file}" ]] || {
  echo "FAIL GOAL-ESCAPE-PROVENANCE: no goal file at ${goal_file}" >&2
  exit 2
}
[[ -d "${workspace_root}" ]] || {
  echo "FAIL GOAL-ESCAPE-PROVENANCE: no workspace root at ${workspace_root}" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Which repository is the commit in? The work happens in sibling checkouts, and
# the goal file may live somewhere else entirely, so the commit is looked up
# rather than assumed: the workspace root first, then every immediate child that
# is a git repository.
# ---------------------------------------------------------------------------
repo=""
if git -C "${workspace_root}" rev-parse --show-toplevel >/dev/null 2>&1 \
  && git -C "${workspace_root}" cat-file -e "${commit}^{commit}" 2>/dev/null; then
  repo="$(git -C "${workspace_root}" rev-parse --show-toplevel)"
else
  while IFS= read -r candidate; do
    [[ -d "${candidate}/.git" || -f "${candidate}/.git" ]] || continue
    if git -C "${candidate}" cat-file -e "${commit}^{commit}" 2>/dev/null; then
      repo="$(git -C "${candidate}" rev-parse --show-toplevel)"
      break
    fi
  done < <(find "${workspace_root}" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
fi

if [[ -z "${repo}" ]]; then
  {
    echo "FAIL GOAL-ESCAPE-PROVENANCE: ${commit} is not a commit in ${workspace_root} or any child repository."
    echo "  a solution commit has to exist where the work is. A commit in a scratch"
    echo "  directory that contains only the goal document proves nothing about the work."
  } >&2
  exit 1
fi

echo "--- GOAL-ESCAPE-PROVENANCE: the solution commit must touch what the goal names ---"
echo ""
echo "  repository: ${repo}"
echo "  commit:     $(git -C "${repo}" show -s --format='%h %s' "${commit}")"
echo ""

mapfile -t changed < <(git -C "${repo}" show --pretty=format: --name-only "${commit}" | sed '/^$/d' | LC_ALL=C sort -u)
if ((${#changed[@]} == 0)); then
  echo "FAIL GOAL-ESCAPE-PROVENANCE: ${commit} changes no files (an empty commit is not a solution)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# The paths the goal names. A goal names files in prose, sometimes with a line
# suffix ("...:205"), sometimes relative to the repository that holds them, so a
# token and a changed path match when one is a path-suffix of the other. Matching
# on the basename alone would make every `default.nix` a hit, so it is not done.
# ---------------------------------------------------------------------------
named_paths="$(
  { grep -oE '[A-Za-z0-9_.@+~/-]+\.(nix|sh|py|ts|md|yml|yaml|json|lock)' "${goal_file}" || true; } \
    | sed -E 's/[.,;:]+$//' \
    | LC_ALL=C sort -u
)"

if [[ -z "${named_paths}" ]]; then
  echo "FAIL GOAL-ESCAPE-PROVENANCE: the goal names no file, so provenance cannot be judged" >&2
  exit 2
fi

# The repositories the goal names. A goal describes a boundary, not a file list:
# it says "at the renderer boundary where those projections are consumed" and
# names the file the derivation lives in, while the crash belongs in the mapping
# that produces it. Measured on this session's own six commits: two of them touch
# only files the goal describes in prose, and a file-only rule rejects them --
# which is why provenance has two tiers and reports which one matched.
named_repos="$(
  { grep -oE 'network-[a-z0-9-]+' "${goal_file}" || true; } | LC_ALL=C sort -u
)"

matches=()
for path in "${changed[@]}"; do
  while IFS= read -r token; do
    [[ -n "${token}" ]] || continue
    # A path the goal names outright: repository-relative
    # (network-renderer-nixos/s88/.../containers.nix) or repository-internal
    # (s88/Unit/mapping/runtime-targets/interfaces/network-behavior.nix).
    if [[ "${path}" == "${token}" ]] \
      || [[ "${path}" == */"${token}" ]] \
      || [[ "${token}" == */"${path}" ]]; then
      matches+=("${path} <- ${token}")
      break
    fi
  done <<<"${named_paths}"
done

repos_matched=()
if ((${#matches[@]} == 0)) || [[ -z "${matches[0]:-}" ]]; then
  repo_name="$(basename "${repo}")"
  if grep -qx "${repo_name}" <<<"${named_repos}"; then
    repos_matched+=("repository ${repo_name} is named by the goal; the changed path(s) are inside it")
  fi
fi

substantive=()
for path in "${changed[@]}"; do
  case "${path}" in
    *.md|*.rst|*.txt) ;;
    *) substantive+=("${path}") ;;
  esac
done

issues=0

if ((${#matches[@]} > 0)); then
  echo "PASS PROVENANCE: ${#matches[@]} changed path(s) are named outright by the goal"
  printf '  %s\n' "${matches[@]}"
elif ((${#repos_matched[@]} > 0)); then
  echo "PASS PROVENANCE (weaker tier): the commit is work in a repository the goal names,"
  echo "  but it touches no file the goal names outright. Acceptable when the goal"
  echo "  describes a boundary rather than a file; the reviewer should look at it."
  printf '  %s\n' "${repos_matched[@]}"
else
  issues=$((issues + 1))
  {
    echo "FAIL PROVENANCE: the commit touches no path the goal names, and is not work"
    echo "  in a repository the goal names."
    echo "  changed:"
    printf '    %s\n' "${changed[@]}"
    echo "  named by the goal:"
    while IFS= read -r token; do echo "    ${token}"; done <<<"${named_paths}"
    echo "  repositories named by the goal: ${named_repos//$'\n'/ }"
    echo "  A commit that touches nothing the goal asked for is not a solution to it."
  } >&2
fi

if ((${#substantive[@]} == 0)); then
  issues=$((issues + 1))
  {
    echo "FAIL SUBSTANCE: every changed path is documentation."
    printf '    %s\n' "${changed[@]}"
    echo "  A completion proof made of a README and a result note is the theatre this"
    echo "  check exists to reject: it is satisfiable without any of the work."
  } >&2
else
  echo "PASS SUBSTANCE: ${#substantive[@]} changed path(s) are not documentation"
  printf '  %s\n' "${substantive[@]}"
fi

echo ""
if ((issues > 0)); then
  echo "FAIL GOAL-ESCAPE-PROVENANCE: ${issues} issue(s); ${commit} is not a completion proof." >&2
  echo "  Give the commit that touched the file the goal names, in the repository that"
  echo "  holds it -- not a commit that records that such a commit exists." >&2
  exit 1
fi

echo "PASS GOAL-ESCAPE-PROVENANCE: ${commit} touches a file the goal names and is not a document alone"
exit 0
