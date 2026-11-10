#!/usr/bin/env bash
set -euo pipefail
# Every secret the s-nodus trial (router-new-test) materializes must be
# decryptable by s-nodus itself, otherwise sops-install-secrets aborts the
# WHOLE manifest on the board and the trial loses internet, WiFi and the
# overlay at once (measured three times: 2026-11-09/10).
#
# s-nodus derives its age key from /persist/root/.ssh/id_ed25519.
S_NODUS_KEY="age1t4rx3z68ax4lqqeeqannm3rfxdza8p7fsvjrjgra6df98ddna37quf028k"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

files=(
  prod-network/testing/secrets/devices/*.sops.yaml
  secrets/s-router-cobalt*.yaml
  secrets/s-router-cobalt*.yml
)
# shellcheck disable=SC2206
files=( ${files[@]} )

missing=0
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  if ! grep -q "$S_NODUS_KEY" "$f"; then
    echo "[hook] sops: s-nodus is not a recipient of $f" >&2
    echo "[hook] sops: run: sops updatekeys -y $f" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "[hook] sops: fix the recipients above and re-stage the files" >&2
  exit 1
fi
exit 0
