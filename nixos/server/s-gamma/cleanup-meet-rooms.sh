#!/usr/bin/env bash
# Remove expired Galene meeting rooms and their persisted recordings/state.
# Each group JSON may carry an RFC3339 "expires" field; once that time has
# passed, the group and its per-group data/recordings directories are removed.
set -euo pipefail

groups_dir="${MEET_GROUPS_DIR:?}"
recordings_dir="${MEET_RECORDINGS_DIR:?}"
data_dir="${MEET_DATA_DIR:?}"

now="$(date -u +%s)"

for group_file in "$groups_dir"/*.json; do
  [ -e "$group_file" ] || continue
  name="$(basename "$group_file" .json)"
  [ -n "$name" ] || continue

  expires="$(jq -r '.expires // empty' "$group_file" 2>/dev/null || true)"
  [ -n "$expires" ] || continue

  expires_epoch="$(date -u -d "$expires" +%s 2>/dev/null || echo 0)"

  if [ "$now" -ge "$expires_epoch" ]; then
    echo "removing expired room: $name (expired $(date -u -d "@$expires_epoch" +%FT%TZ))"
    rm -f "$group_file" "$groups_dir/$name.ics"
    rm -rf "$recordings_dir/$name"
    rm -rf "$data_dir/$name"
  fi
done
