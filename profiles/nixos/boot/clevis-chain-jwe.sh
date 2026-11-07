#!/usr/bin/env nix-shell
#!nix-shell -i bash -p clevis cryptsetup curl coreutils util-linux tpm2-tools
#
# Create a A chained Clevis binding: Tang AND this machine's TPM2, both required.
#
# The output is a JWE whose Clevis pin is `sss` with threshold `t = 2` over two
# shares:
#
#   * a `tang` share  -- recovered from the Tang server over the network
#   * a `tpm2` share  -- sealed to this machine's TPM, bound to the given PCRs
#
# Because the threshold equals the number of shares, `clevis decrypt` can only
# reconstruct the LUKS key when the Tang server answers *and* the local TPM
# unseals its share. One factor alone is not enough: a stolen disk cannot be
# opened with just the TPM, and the Tang server alone cannot open it either.
#
# Usage:
#   sudo ./clevis-chain-jwe.sh --url http://host:7500 \
#        [--pcr 7] [--source-jwe FILE | --passphrase] [--out FILE]
#
#   --url URL         Tang server to bind. Repeatable; every URL is tried, and
#                     the Tang side needs any one of them (default threshold is
#                     still 2 total: one Tang share + the TPM share).
#   --pcr LIST        PCRs the TPM share is sealed to (default: 7, the Secure
#                     Boot state PCR; it is the only PCR that is stable across
#                     reboots when firmware/boot entries do not change).
#   --source-jwe FILE Take the LUKS keyslot secret from an existing Clevis JWE
#                     instead of prompting for the passphrase. Requires that
#                     JWE to be decryptable right now (its Tang must be
#                     reachable). This is how you chain an existing binding
#                     without touching the LUKS header at all.
#   --passphrase      Ask for an existing LUKS passphrase and add the chained
#                     binding as a NEW keyslot instead of reusing a secret.
#   --out FILE        Where to write the JWE (default ./root-chain.jwe).
#
# With `--source-jwe` the LUKS header is not modified: the same keyslot secret
# is re-wrapped into the chained JWE, which is what `secretFiles` in
# profiles/nixos/boot/clevis-tang-unlock.nix expects.
#
# Exit codes: 0 ok, 1 usage/environment error, 2 the chained JWE could not be
# produced, 3 the produced JWE failed to decrypt back to the same secret.
set -euo pipefail

URLS=()
PCRS=7
OUT="./root-chain.jwe"
SOURCE_JWE=""
USE_PASSPHRASE=0
LUKS_DEV="${LUKS_DEV:-}"

die() {
  echo "clevis-chain-jwe: $*" >&2
  exit "${2:-1}"
}

usage() {
  sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --url)
      [ $# -ge 2 ] || die "--url needs an argument"
      URLS+=("$2")
      shift 2
      ;;
    --pcr)
      [ $# -ge 2 ] || die "--pcr needs an argument"
      PCRS="$2"
      shift 2
      ;;
    --source-jwe)
      [ $# -ge 2 ] || die "--source-jwe needs an argument"
      SOURCE_JWE="$2"
      shift 2
      ;;
    --passphrase)
      USE_PASSPHRASE=1
      shift
      ;;
    --out)
      [ $# -ge 2 ] || die "--out needs an argument"
      OUT="$2"
      shift 2
      ;;
    -h | --help) usage 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "must run as root (the TPM device is root-only)"
[ "${#URLS[@]}" -gt 0 ] || die "at least one --url is required"
if [ -z "$SOURCE_JWE" ] && [ "$USE_PASSPHRASE" -eq 0 ]; then
  die "pick one of --source-jwe FILE or --passphrase"
fi
if [ -n "$SOURCE_JWE" ] && [ "$USE_PASSPHRASE" -eq 1 ]; then
  die "--source-jwe and --passphrase are mutually exclusive"
fi
[ -e /dev/tpmrm0 ] || [ -e /dev/tpm0 ] \
  || die "no TPM device; the tpm2 share cannot be created"

# The Tang side must be reachable now, otherwise the share cannot be created.
for url in "${URLS[@]}"; do
  echo "clevis-chain-jwe: checking Tang advertisement at $url" >&2
  curl -fsS "$url/adv" >/dev/null || die "Tang not reachable at $url"
done

work=$(mktemp -d)
secret=""
cleanup() {
  # Overwrite before unlinking: the working directory holds the LUKS key.
  if [ -n "$secret" ] && [ -f "$secret" ]; then
    dd if=/dev/urandom of="$secret" bs=1 count="$(stat -c %s "$secret" 2>/dev/null || echo 1)" \
      conv=notrunc status=none 2>/dev/null || true
  fi
  unset CLEVIS_PASS EXISTING_LUKS_PASS
  rm -rf "$work"
}
trap cleanup EXIT
chmod 700 "$work"

tang_pins=""
for url in "${URLS[@]}"; do
  tang_pins+="{\"url\":\"$url\"},"
done
tang_pins="${tang_pins%,}"

# threshold 2 == "one Tang share AND the TPM share"; add more URLs and the Tang
# side still only needs one of them because they are grouped in one pin.
sss_cfg="{\"t\":2,\"pins\":{\"tang\":[$tang_pins],\"tpm2\":{\"pcr_ids\":\"$PCRS\"}}}"

if [ -n "$SOURCE_JWE" ]; then
  [ -r "$SOURCE_JWE" ] || die "cannot read $SOURCE_JWE"
  echo "clevis-chain-jwe: recovering the keyslot secret from $SOURCE_JWE" >&2
  clevis decrypt <"$SOURCE_JWE" >"$work/secret.bin" \
    || die "could not decrypt $SOURCE_JWE (is its Tang reachable?)" 2
else
  [ -n "$LUKS_DEV" ] || die "LUKS_DEV must name the LUKS device for --passphrase"
  [ -b "$LUKS_DEV" ] || die "no such block device: $LUKS_DEV"
  read -r -s -p "Enter CURRENT LUKS passphrase: " EXISTING_LUKS_PASS
  echo
  [ -n "$EXISTING_LUKS_PASS" ] || die "empty passphrase"

  # A random key becomes the new keyslot; the chained JWE wraps that key, so
  # neither the passphrase nor the TPM ever see each other.
  CLEVIS_PASS="$(head -c 32 /dev/urandom | base64)"
  printf '%s' "$CLEVIS_PASS" >"$work/secret.bin"

  printf '%s' "$EXISTING_LUKS_PASS" |
    cryptsetup luksAddKey --key-file - "$LUKS_DEV" "$work/secret.bin" \
      || die "could not add the new keyslot" 2
  echo "clevis-chain-jwe: added a new LUKS keyslot" >&2
fi
secret="$work/secret.bin"
echo "clevis-chain-jwe: share secret is $(stat -c %s "$secret") bytes" >&2

echo "clevis-chain-jwe: sealing to PCR $PCRS and to ${#URLS[@]} Tang URL(s)" >&2
clevis encrypt sss "$sss_cfg" -y <"$secret" >"$work/chain.jwe" 2>"$work/enc.err" || {
  cat "$work/enc.err" >&2
  die "clevis encrypt sss failed" 2
}

# Round-trip before installing it: a JWE that cannot decrypt is worse than no
# binding at all, because it silently costs a boot its automatic unlock.
echo "clevis-chain-jwe: verifying the chained JWE round-trips" >&2
clevis decrypt <"$work/chain.jwe" >"$work/back.bin" 2>"$work/dec.err" || {
  cat "$work/dec.err" >&2
  die "the freshly generated chained JWE does not decrypt" 3
}
cmp -s "$secret" "$work/back.bin" || die "round-trip produced a different secret" 3

install -m 0400 "$work/chain.jwe" "$OUT"
echo "clevis-chain-jwe: wrote $OUT" >&2
echo >&2
echo "Next steps:" >&2
echo "  1. Stage it: local.boot.clevisTangUnlock.secretFiles = [ $OUT ];" >&2
echo "  2. Set   : local.boot.clevisTangUnlock.tpm2 = \"chain\";" >&2
echo "  3. Do NOT set tpm2-device=auto on this device's crypttabExtraOpts — a" >&2
echo "     legacy systemd-tpm2 token would unlock the disk without Tang and" >&2
echo "     defeat the chain. Wipe any such token with" >&2
echo "       systemd-cryptenroll --wipe-slot=<n> <device>" >&2
