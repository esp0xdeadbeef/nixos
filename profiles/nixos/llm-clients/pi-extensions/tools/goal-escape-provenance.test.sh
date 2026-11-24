#!/usr/bin/env bash
# GAMP-SCOPE: process control; the provenance check can fire and can pass
#
# scripts/goal-escape-provenance.sh exists because a completion proof was once
# satisfied by `git init` in a scratch directory plus a commit of the goal
# document and a result note: the accepted "solution" was a pointer, and every
# repository the work was actually in was irrelevant to it. That is theatre: the
# same proof is available to a run that did nothing.
#
# This case proves the replacement check is not itself theatre, in the only way
# that means anything: it must FAIL on the exact shape that was accepted, FAIL on
# each half of the condition separately, and PASS on real work. A check that
# cannot pass is a wall, and a check that cannot fail is decoration; the four
# seeded cases below are what distinguish them.
#
# Hermetic by construction: a throwaway workspace, two throwaway repositories and
# a synthetic goal document under $TMPDIR. Nothing here reads the real checkout,
# so it runs identically on a runner.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
script="${repo_root}/profiles/nixos/llm-clients/pi-extensions/tools/goal-escape-provenance.sh"

echo "--- GOAL-ESCAPE-PROVENANCE: the check fires on theatre and passes on work ---"
echo ""

[[ -x "${script}" ]] || {
  echo "FAIL GOAL-ESCAPE-PROVENANCE: no executable script at ${script}" >&2
  exit 1
}

issues=0
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

export GIT_AUTHOR_NAME=provenance-test GIT_AUTHOR_EMAIL=provenance@example.invalid
export GIT_COMMITTER_NAME=provenance-test GIT_COMMITTER_EMAIL=provenance@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

workspace="${work}/workspace"
mkdir -p "${workspace}"

# A goal that names two files in one repository, in the two shapes the real goal
# uses: repository-relative, and relative to the repository root.
cat >"${work}/GOAL.md" <<'GOAL'
# Synthetic goal
The model half lives at repo-a/src/thing.nix:12 and the render half at
s88/render/thing-render.nix. Nothing else is part of this goal.
GOAL

repo_a="${workspace}/repo-a"
mkdir -p "${repo_a}/src" "${repo_a}/s88/render" "${repo_a}/docs"
git -C "${repo_a}" init -q .
printf 'original\n' >"${repo_a}/src/thing.nix"
printf 'original\n' >"${repo_a}/s88/render/thing-render.nix"
git -C "${repo_a}" add -A
git -C "${repo_a}" commit -q -m "seed: the files the goal names"

# A scratch directory holding only the goal document, exactly the accepted shape.
theatre="${work}/theatre"
mkdir -p "${theatre}"
git -C "${theatre}" init -q .
cp "${work}/GOAL.md" "${theatre}/GOAL.md"
printf 'we did it\n' >"${theatre}/RESULT.md"
git -C "${theatre}" add -A
git -C "${theatre}" commit -q -m "record the result"
theatre_commit="$(git -C "${theatre}" rev-parse HEAD)"

# CASE 1 -- real work on a named file: PASS.
printf 'crash\n' >>"${repo_a}/src/thing.nix"
git -C "${repo_a}" commit -q -am "make the model half crash"
work_commit="$(git -C "${repo_a}" rev-parse HEAD)"

out="$(bash "${script}" "${work}/GOAL.md" "${work_commit}" "${workspace}" 2>&1 || true)"
if ! grep -q '^PASS GOAL-ESCAPE-PROVENANCE' <<<"${out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: real work on a file the goal names was rejected"
    echo "${out}"
  } >&2
else
  echo "PASS CASE 1: a commit touching a file the goal names, and not a document, is accepted"
fi

# CASE 2 -- the accepted theatre: a scratch repo with the goal document and a
# result note. It must not be found, must have no provenance, and must have no
# substance. Any of those three rejections is the check working.
out="$(bash "${script}" "${work}/GOAL.md" "${theatre_commit}" "${workspace}" 2>&1 || true)"
if grep -q '^PASS GOAL-ESCAPE-PROVENANCE' <<<"${out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 2: the theatre shape (git init in a scratch dir + a result note) was accepted"
    echo "${out}"
  } >&2
elif ! grep -qE 'FAIL (PROVENANCE|SUBSTANCE|GOAL-ESCAPE-PROVENANCE)' <<<"${out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 2: the theatre shape failed for no stated reason"
    echo "${out}"
  } >&2
else
  echo "PASS CASE 2: the theatre shape is rejected, and the rejection is stated"
fi

# CASE 3 -- substance without provenance: a real source change, in a repository
# the goal does not name. Work, but not this goal's work; it must be rejected.
repo_b="${workspace}/repo-b"
mkdir -p "${repo_b}/src"
git -C "${repo_b}" init -q .
printf 'seed\n' >"${repo_b}/src/other.nix"
git -C "${repo_b}" add -A
git -C "${repo_b}" commit -q -m "seed: another repository"
printf 'unrelated\n' >>"${repo_b}/src/other.nix"
git -C "${repo_b}" commit -q -am "change something the goal did not ask for"
unrelated_commit="$(git -C "${repo_b}" rev-parse HEAD)"

out="$(bash "${script}" "${work}/GOAL.md" "${unrelated_commit}" "${workspace}" 2>&1 || true)"
if ! grep -q 'FAIL PROVENANCE' <<<"${out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 3: a source change in a repository the goal does not name passed provenance"
    echo "${out}"
  } >&2
else
  echo "PASS CASE 3: real work in a repository the goal does not name fails provenance"
fi

# CASE 6 -- the weaker tier, and the reason it exists. A commit inside a
# repository the goal names, touching a source file the goal does not name
# outright: a goal that describes a boundary cannot enumerate every file the
# boundary reaches. The check accepts it and SAYS the evidence is the weaker
# tier, so the reviewer knows to look.
printf 'boundary work\n' >>"${repo_b}/src/other.nix"
printf 'changed\n' >>"${repo_a}/src/thing.nix"
git -C "${repo_a}" commit -q -am "work at the boundary the goal describes"
boundary_commit="$(git -C "${repo_a}" rev-parse HEAD)"

out="$(bash "${script}" "${work}/GOAL.md" "${boundary_commit}" "${workspace}" 2>&1 || true)"
if ! grep -q '^PASS PROVENANCE' <<<"${out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 6: work in a repository the goal names was rejected"
    echo "${out}"
  } >&2
else
  echo "PASS CASE 6: work in a repository the goal names is accepted (the tier is stated)"
fi

# CASE 4 -- provenance without substance: the goal names a document, and the
# commit only edits it. Provenance is satisfied and substance is not, which is
# why the two conditions are separate.
cat >"${work}/GOAL-DOC.md" <<'GOAL'
# Synthetic goal
The requirement is written in repo-a/docs/REQUIREMENT.md and nowhere else.
GOAL
mkdir -p "${repo_a}/docs"
printf 'requirement\n' >"${repo_a}/docs/REQUIREMENT.md"
git -C "${repo_a}" add -A
git -C "${repo_a}" commit -q -m "seed: the requirement document"
printf 'clarified\n' >>"${repo_a}/docs/REQUIREMENT.md"
git -C "${repo_a}" commit -q -am "clarify the requirement"
doc_commit="$(git -C "${repo_a}" rev-parse HEAD)"

out="$(bash "${script}" "${work}/GOAL-DOC.md" "${doc_commit}" "${workspace}" 2>&1 || true)"
if ! grep -q 'FAIL SUBSTANCE' <<<"${out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 4: a documentation-only commit on a named file passed substance"
    echo "${out}"
  } >&2
else
  echo "PASS CASE 4: a documentation-only commit on a named file fails substance"
fi

# CASE 5 -- a commit that exists nowhere in the workspace. Written because the
# first escape in this session named a commit in a directory outside every real
# repository, and nothing noticed.
out="$(bash "${script}" "${work}/GOAL.md" "${theatre_commit}" "${repo_a}" 2>&1 || true)"
if ! grep -q 'is not a commit in' <<<"${out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 5: a commit outside the workspace subtree was not reported as missing"
    echo "${out}"
  } >&2
else
  echo "PASS CASE 5: a commit in a scratch repository is not accepted as the workspace's work"
fi

# CASE 7 -- the other half of the proof: a record that quotes the goal's digest
# passes the digest check. The digest moved twice in one session, so a record can
# quote a document that no longer exists and still look verified.
good_record="${work}/RECORD-good.md"
printf '# result\n\n    cat ${work}/GOAL.md | sha256sum\n%s  -\n' "$(cat "${work}/GOAL.md" | sha256sum | cut -d' ' -f1)" >"${good_record}"
out="$(bash "${script}" --check-digest "${work}/GOAL.md" "${good_record}" 2>&1 || true)"
if ! grep -q '^PASS DIGEST' <<<"${out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 7: a record quoting the goal's own digest was rejected"
    echo "${out}"
  } >&2
else
  echo "PASS CASE 7: a record quoting the goal's digest passes"
fi

# CASE 8 -- the stale digest. Measured in this session: a record quoted 43511b04
# for a goal whose digest had moved to 98e9384c, and nothing noticed.
stale_record="${work}/RECORD-stale.md"
printf '# result\n\n    cat ${work}/GOAL.md | sha256sum\n%s  -\n' "$(printf 'a goal that no longer exists\n' | sha256sum | cut -d' ' -f1)" >"${stale_record}"
out="$(bash "${script}" --check-digest "${work}/GOAL.md" "${stale_record}" 2>&1 || true)"
if ! grep -q '^FAIL DIGEST' <<<"${out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 8: a record quoting only a stale digest was accepted"
    echo "${out}"
  } >&2
else
  echo "PASS CASE 8: a record quoting only a stale digest is rejected"
fi

echo ""
if ((issues > 0)); then
  echo "FAIL GOAL-ESCAPE-PROVENANCE: ${issues} case(s) did not behave as stated." >&2
  exit 1
fi

echo "PASS GOAL-ESCAPE-PROVENANCE: the check accepts real work and rejects a pointer document"
exit 0
