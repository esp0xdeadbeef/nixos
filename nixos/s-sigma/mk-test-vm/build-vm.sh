#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Configuration
###############################################################################

VM_NAME="${VM_NAME:-nixos-testvm}"

VM_DIR="${VM_DIR:-/vmstore/$VM_NAME}"
BUILD_DIR="${BUILD_DIR:-$VM_DIR/builds}"

MEMORY="${MEMORY:-1024}"
VCPUS="${VCPUS:-2}"
OS_VARIANT="${OS_VARIANT:-nixos-unstable}"

BRIDGE1="${BRIDGE1:-vmbr4}"
BRIDGE2="${BRIDGE2:-vmbr0}"

KEEP_BUILDS="${KEEP_BUILDS:-5}"

###############################################################################
# Helpers
###############################################################################

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(date -Is)" "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

vm_exists() {
  virsh dominfo "$VM_NAME" &>/dev/null
}

vm_state() {
  virsh domstate "$VM_NAME" 2>/dev/null | tr -d '\r'
}

vm_running() {
  [[ "$(vm_state)" == "running" ]]
}

vm_root_disk() {
  virsh domblklist "$VM_NAME" --details \
    | awk '
        NR>2 && $2=="disk" {
          print $3 "|" $4
          exit
        }'
}

find_built_qcow2() {
  find -L result -type f -name '*.qcow2' | head -n1
}

gc_old_builds() {
  [[ -d "$BUILD_DIR" ]] || return 0
  mapfile -t files < <(ls -1t "$BUILD_DIR"/*.qcow2 2>/dev/null || true)
  if (( ${#files[@]} > KEEP_BUILDS )); then
    for f in "${files[@]:$KEEP_BUILDS}"; do
      log "GC: removing old build $f"
      rm -f -- "$f"
    done
  fi
}

###############################################################################
# Preflight
###############################################################################

need nix
need virsh
need virt-install
need awk
need find
need cp

mkdir -p "$BUILD_DIR"

###############################################################################
# Build qcow2
###############################################################################

log "Building Nix image…"
NIXPKGS_ALLOW_UNFREE=1 nix build --impure -L

QCOW_PATH="$(find_built_qcow2 || true)"
[[ -n "${QCOW_PATH:-}" ]] || die "qcow2 not found under ./result"

STAMP="$(date +%Y%m%d-%H%M%S)"
NEW_IMG="$BUILD_DIR/${VM_NAME}.${STAMP}.qcow2"

log "Copying built qcow2 to: $NEW_IMG"
cp -f -- "$QCOW_PATH" "$NEW_IMG"
chmod 600 "$NEW_IMG"

###############################################################################
# Create / Switch
###############################################################################

if vm_exists; then
  STATE="$(vm_state)"
  log "Domain '$VM_NAME' exists (state: $STATE)"

  if vm_running; then
    ROOT_INFO="$(vm_root_disk)"
    [[ -n "$ROOT_INFO" ]] || die "Could not determine root disk"

    ROOT_DEV="${ROOT_INFO%%|*}"
    OLD_IMG="${ROOT_INFO##*|}"

    log "Live disk pivot"
    log "  device: $ROOT_DEV"
    log "  old:    $OLD_IMG"
    log "  new:    $NEW_IMG"

    virsh blockcopy \
      "$VM_NAME" "$ROOT_DEV" "$NEW_IMG" \
      --pivot \
      --verbose
    virsh blockcopy \
      "$VM_NAME" "$ROOT_DEV" "$NEW_IMG" \
      --active \
      --persistent \
      --pivot \
      --verbose


    log "Live pivot completed"

  else
    ROOT_INFO="$(vm_root_disk || true)"
    [[ -n "$ROOT_INFO" ]] && ROOT_DEV="${ROOT_INFO%%|*}" || ROOT_DEV="vda"

    log "Cold disk swap (persistent)"
    log "  device: $ROOT_DEV"
    log "  new:    $NEW_IMG"

    virsh detach-disk "$VM_NAME" "$ROOT_DEV" --persistent || true
    virsh attach-disk \
      "$VM_NAME" "$NEW_IMG" "$ROOT_DEV" \
      --targetbus virtio \
      --persistent

    virsh start "$VM_NAME"
    log "Started '$VM_NAME'"
  fi
else
  log "Domain '$VM_NAME' does not exist; creating"

  virt-install \
    --name "$VM_NAME" \
    --memory "$MEMORY" \
    --vcpus "$VCPUS" \
    --disk "path=$NEW_IMG,format=qcow2,bus=virtio" \
    --boot uefi \
    --os-variant "$OS_VARIANT" \
    --network "bridge=$BRIDGE1,model=virtio" \
    --network "bridge=$BRIDGE2,model=virtio" \
    --console pty,target_type=serial \
    --noautoconsole \
    --import

  log "Created '$VM_NAME'"
fi

###############################################################################
# Cleanup
###############################################################################

gc_old_builds
log "Done."

