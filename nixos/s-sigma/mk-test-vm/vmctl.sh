#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# REQUIRED ENV (provided by nix develop)
###############################################################################
: "${OVMF_CODE:?Run via nix develop (OVMF_CODE not set)}"
: "${OVMF_VARS_TEMPLATE:?Run via nix develop (OVMF_VARS_TEMPLATE not set)}"

###############################################################################
# CONFIG
###############################################################################
VM_NAME="${VM_NAME:-nixos-testvm}"
VM_DIR="${VM_DIR:-/vmstore/$VM_NAME}"
BUILD_DIR="${BUILD_DIR:-$VM_DIR/builds}"

MEM_MIB="${MEM_MIB:-1024}"
VCPUS="${VCPUS:-2}"
BRIDGE1="${BRIDGE1:-vmbr4}"
BRIDGE2="${BRIDGE2:-vmbr0}"

XML_TEMPLATE="${XML_TEMPLATE:-./vm.xml.in}"

###############################################################################
# HELPERS
###############################################################################
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(date -Is)" "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

vm_defined() { virsh dominfo "$VM_NAME" &>/dev/null; }
vm_running() {
  [[ "$(virsh domstate "$VM_NAME" 2>/dev/null | tr -d '\r')" == "running" ]]
}

ensure_dirs() {
  mkdir -p "$VM_DIR" "$BUILD_DIR"
}

###############################################################################
# OVMF VARS
###############################################################################
ensure_nvram() {
  local vars="$VM_DIR/OVMF_VARS.fd"
  if [[ ! -f "$vars" ]]; then
    log "Creating persistent OVMF VARS: $vars"
    cp -f "$OVMF_VARS_TEMPLATE" "$vars"
    chmod 600 "$vars"
  fi
  echo "$vars"
}

###############################################################################
# BUILD QCOW (flake output .#vm)
###############################################################################
build_qcow_store_path() {
  need nix

  log "Building qcow2 via flake output .#vm"
  nix build --impure -L .#vm

  local qcow
  qcow="$(find -L ./result -type f -name '*.qcow2' | head -n1 || true)"
  [[ -n "${qcow:-}" ]] || die "No *.qcow2 found under ./result after build"
  echo "$qcow"
}

###############################################################################
# XML RENDERING (NO sed)
###############################################################################
render_xml() {
  need python3

  local disk_path="$1"
  local ovmf_vars="$2"
  local out="$3"

  python3 - "$XML_TEMPLATE" "$out" <<'PY' \
"$VM_NAME" "$MEM_MIB" "$VCPUS" "$OVMF_CODE" "$ovmf_vars" "$disk_path" "$BRIDGE1" "$BRIDGE2"
import sys, pathlib

tmpl = pathlib.Path(sys.argv[1]).read_text()
outp = pathlib.Path(sys.argv[2])

(vm, mem, vcpus, ovmf_code, ovmf_vars, disk, br1, br2) = sys.argv[3:11]

repl = {
  "@VM_NAME@": vm,
  "@MEM_MIB@": mem,
  "@VCPUS@": vcpus,
  "@OVMF_CODE@": ovmf_code,
  "@OVMF_VARS@": ovmf_vars,
  "@DISK_PATH@": disk,
  "@BRIDGE1@": br1,
  "@BRIDGE2@": br2,
}

for k, v in repl.items():
  tmpl = tmpl.replace(k, v)

outp.write_text(tmpl)
PY
}

###############################################################################
# COMMANDS
###############################################################################
cmd_build() {
  build_qcow_store_path >/dev/null
  log "Build complete."
}

cmd_start() {
  need virsh
  ensure_dirs

  if vm_defined; then
    die "Domain '$VM_NAME' is already defined.
Transient mode requires it to be undefined.

Fix:
  virsh shutdown '$VM_NAME' || true
  virsh undefine '$VM_NAME' --nvram
Then rerun: $0 start"
  fi

  local base_qcow
  base_qcow="$(build_qcow_store_path)"

  local disk="$VM_DIR/current.qcow2"
  if [[ ! -f "$disk" ]]; then
    log "Seeding initial disk: $disk"
    cp -f "$base_qcow" "$disk"
    chmod 600 "$disk"
  else
    log "Using existing disk: $disk"
  fi

  local ovmf_vars
  ovmf_vars="$(ensure_nvram)"

  local xml="$VM_DIR/$VM_NAME.transient.xml"
  render_xml "$disk" "$ovmf_vars" "$xml"

  log "Starting transient VM: $VM_NAME"
  virsh create "$xml"
  log "Started."
}

cmd_hotswap() {
  need virsh
  ensure_dirs

  vm_running || die "VM '$VM_NAME' is not running. Start it first: $0 start"

  local src
  src="$(virsh domblklist "$VM_NAME" --details \
          | awk 'NR>2 && $2=="disk" && $3=="vda" {print $4; exit}')"
  [[ -n "${src:-}" ]] || die "Could not determine current vda source path"

  local stamp dest
  stamp="$(date +%Y%m%d-%H%M%S)"
  dest="$BUILD_DIR/${VM_NAME}.${stamp}.qcow2"

  log "Live disk hotswap (blockcopy + pivot)"
  log "  src:  $src"
  log "  dest: $dest"

  virsh blockcopy \
    "$VM_NAME" vda "$dest" \
    --format qcow2 \
    --pivot \
    --verbose

  log "Pivot complete. Current disk mapping:"
  virsh domblklist "$VM_NAME" --details || true
}

cmd_status() {
  need virsh

  if vm_defined; then
    log "Defined: yes"
  else
    log "Defined: no (transient mode)"
  fi

  if vm_running; then
    log "State: running"
    virsh domblklist "$VM_NAME" --details || true
  else
    log "State: not running"
  fi
}

###############################################################################
# DISPATCH
###############################################################################
case "${1:-}" in
  build)   cmd_build ;;
  start)   cmd_start ;;
  hotswap) cmd_hotswap ;;
  status)  cmd_status ;;
  *)
    cat <<EOF
Usage (run inside: nix develop):

  $0 build      # build qcow2 via nixos-generators (.#vm)
  $0 start      # start transient VM
  $0 hotswap    # live disk file swap (blockcopy + pivot)
  $0 status

Env:
  VM_NAME, VM_DIR, MEM_MIB, VCPUS, BRIDGE1, BRIDGE2, XML_TEMPLATE
EOF
    exit 2
    ;;
esac

