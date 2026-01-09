#!/usr/bin/env bash
set -euo pipefail

VM_NAME="nixos-testvm"
IMG="./nixos.qcow2"

NIXPKGS_ALLOW_UNFREE=1 nix build --impure -L

QCOW_PATH="$(find -L result -type f -name '*.qcow2' | head -n1)"
if [[ -z "$QCOW_PATH" ]]; then
  echo "ERROR: qcow2 not found"
  exit 1
fi

cp -f "$QCOW_PATH" "$IMG"
chmod 600 "$IMG"

virt-install \
  --name "$VM_NAME" \
  --memory 1024 \
  --vcpus 2 \
  --disk "path=$IMG,format=qcow2,bus=virtio" \
  --boot uefi \
  --os-variant nixos-unstable \
  --network bridge=vmbr4,model=virtio \
  --network bridge=vmbr0,model=virtio \
  --console pty,target_type=serial \
  --noautoconsole \
  --import

