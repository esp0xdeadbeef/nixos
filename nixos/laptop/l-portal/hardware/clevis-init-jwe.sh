#!/usr/bin/env nix-shell
#!nix-shell -i bash -p clevis cryptsetup curl coreutils util-linux

set -euo pipefail

# Space-separated list of Tang servers bound into a single SSS pin with
# threshold 1 (any one reachable Tang suffices at unlock time). Defaults to
# the neon Tang plus the cobalt unlock-plane Tang.
TANG_URLS="${TANG_URLS:-http://192.168.1.75:7500 http://10.2.90.10:7500}"
LUKS_DEV="/dev/disk/by-partlabel/disk-nvme0n1-luks"
JWE_OUT="./root.jwe"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

if [[ ! -b "$LUKS_DEV" ]]; then
  echo "LUKS device not found: $LUKS_DEV" >&2
  exit 1
fi

read -r -a urls <<< "$TANG_URLS"
if [[ ${#urls[@]} -eq 0 ]]; then
  echo "TANG_URLS must list at least one Tang URL" >&2
  exit 1
fi

for url in "${urls[@]}"; do
  echo "Checking Tang advertisement at $url..."
  curl -fsS "$url/adv" >/dev/null
done

echo
read -r -s -p "Enter CURRENT LUKS passphrase: " EXISTING_LUKS_PASS
echo

if [[ -z "$EXISTING_LUKS_PASS" ]]; then
  echo "Empty passphrase not allowed" >&2
  exit 1
fi

cleanup() {
  unset EXISTING_LUKS_PASS CLEVIS_PASS
}
trap cleanup EXIT

# Build an SSS pin with threshold 1 over every Tang URL: the generated key is
# recoverable if ANY bound Tang server is reachable during initrd unlock.
pins=""
for url in "${urls[@]}"; do
  pins+="{\"url\":\"$url\"},"
done
pins="${pins%,}"
sss_cfg="{\"t\":1,\"pins\":{\"tang\":[$pins]}}"

CLEVIS_PASS="$(head -c 32 /dev/urandom | base64)"

printf '%s' "$CLEVIS_PASS" \
  | clevis encrypt sss "$sss_cfg" -y \
  > "$JWE_OUT"

printf '%s' "$EXISTING_LUKS_PASS" \
  | cryptsetup luksAddKey "$LUKS_DEV" \
    --key-file - \
    <(printf '%s' "$CLEVIS_PASS")

printf '%s' "$CLEVIS_PASS" \
  | cryptsetup open --test-passphrase "$LUKS_DEV"

echo "Clevis key added and verified"
echo "JWE stored at: $JWE_OUT"
