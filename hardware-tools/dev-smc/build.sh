#!/usr/bin/env bash
# Build the /dev/smc test module against the RUNNING kernel, out of tree.
#
# The kernel `dev` output is published at /etc/kernel-dev/source by the
# hardware.bananapi.bpi-r4-pro module, so this needs no nixos-rebuild:
# a module rebuild is ~2 s instead of a full kernel rebuild.
#
#   ./build.sh          build dev_smc.ko
#   ./build.sh insmod   build and load
#   ./build.sh rmmod    unload
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KVER="$(uname -r)"

DEV_ROOT="${KERNEL_DEV:-/etc/kernel-dev/source}"
if [ ! -d "$DEV_ROOT" ]; then
  echo "!! no kernel dev tree at $DEV_ROOT" >&2
  echo "   the board config publishes kernelPackages.kernel.dev there;" >&2
  echo "   set KERNEL_DEV= if you are building elsewhere." >&2
  exit 1
fi

BUILDDIR="$(find "$DEV_ROOT/lib/modules" -maxdepth 2 -name build -type d 2>/dev/null | head -1)"
[ -n "$BUILDDIR" ] || {
  echo "!! no build/ under $DEV_ROOT/lib/modules" >&2
  ls "$DEV_ROOT/lib/modules" >&2
  exit 1
}

echo ">> kernel  : $KVER"
echo ">> builddir: $BUILDDIR"

make -C "$BUILDDIR" M="$HERE" modules

case "${1:-}" in
  insmod)
    sudo insmod "$HERE/dev_smc.ko"
    ls -l /dev/smc
    ;;
  rmmod)
    sudo rmmod dev_smc
    ;;
  "")
    echo ">> built: $HERE/dev_smc.ko"
    echo "   load with: $0 insmod"
    ;;
  *)
    echo "unknown argument: $1" >&2
    exit 2
    ;;
esac
