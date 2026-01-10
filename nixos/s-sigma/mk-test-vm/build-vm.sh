#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${VM_NAME:-nixos-testvm}"
VMSTORE_BASE="/vmstore"

VM_DIR="${VMSTORE_BASE}/${VM_NAME}"
BUILD_DIR="${VM_DIR}/build"
RESULT_LINK="${BUILD_DIR}/result"
FINAL_IMG="${BUILD_DIR}/disk.img"

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(date -Is)" "$*" >&2; exit 1; }

mkdir -p "$BUILD_DIR"

log "Removing old result link"
rm -f "$RESULT_LINK"

log "Building raw EFI image (.#rawEfi)"
NIXPKGS_ALLOW_UNFREE=1 \
  nix build --impure -L .#rawEfi --out-link "$RESULT_LINK"

IMG="$(find -L "$RESULT_LINK" -maxdepth 1 -name '*.img' | head -n1)"
[[ -n "$IMG" ]] || die "No .img produced"

log "Installing disk to VM store"
rm -f "$FINAL_IMG"
cp -f "$(realpath "$IMG")" "$FINAL_IMG"
chmod 600 "$FINAL_IMG"

log "Done"
log "Disk ready at: $FINAL_IMG"

