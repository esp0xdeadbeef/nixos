#!/usr/bin/env bash
# Deterministically pick a non-blank, printable-ASCII SSID from a list.
#
# Usage: derive-ssid.sh SEED PLANE LIST USEDFILE
#   SEED      - shared secret seed (from SOPS)
#   PLANE     - e.g. "clients", "clients-vpn", "mgmt", "unlock"
#   LIST      - path to the vendored ssids.txt
#   USEDFILE  - state file tracking SSIDs already selected (for collision-free)
set -euo pipefail

seed="$1"
plane="$2"
list="$3"
used="$4"

[ -n "$seed" ] || { echo "derive-ssid: empty seed (refusing to derive)" >&2; exit 1; }
[ -n "$plane" ] || { echo "derive-ssid: empty plane" >&2; exit 1; }

mapfile -t ssids < <(tr -d '\r' < "$list" | grep -E '^[[:print:]]+$' | grep -v '^[[:space:]]*$')
n=${#ssids[@]}
[ "$n" -gt 0 ] || { echo "derive-ssid: no usable SSIDs in $list" >&2; exit 1; }

h=$(printf '%s:%s' "$seed" "$plane" | sha256sum | awk '{print $1}')
idx=$(( (16#${h:0:8}) % n ))

# Linear-probe past any SSID already selected for another plane.
while grep -qxF "${ssids[$idx]}" "$used" 2>/dev/null; do
  idx=$(( (idx + 1) % n ))
done

printf '%s\n' "${ssids[$idx]}" | tee -a "$used"
