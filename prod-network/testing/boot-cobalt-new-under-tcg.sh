#!/usr/bin/env bash
# Boot an aarch64 router VM image under pure QEMU TCG on an x86_64 host.
#
# Why this exists
# ---------------
# The generated `bin/run-<vm>-vm` runner is an aarch64 build: it execs
# aarch64 coreutils, so on an x86_64 host it dies immediately with
#
#   /nix/store/...-coreutils/bin/readlink: cannot execute binary file: Exec format error
#
# unless `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` is enabled. That
# is fine on a workstation, but binfmt needs root and is a persistent host
# change. This script avoids both: it re-implements the runner's QEMU
# invocation directly, using the x86_64 `qemu-system-aarch64` in TCG mode,
# and boots the guest kernel + initrd + store share by hand.
#
# What it is good for
# -------------------
#   * proving the guest's kernel/init/userspace actually boot
#   * seeing every container start and where it fails
#   * measuring boot time and per-unit ordering
#   * reading systemd failure output without touching any real host
#
# What it is NOT
# --------------
# It uses `-netdev user`, not the real `br-cobalt-lan` / `br-cobalt-wan`
# bridges, so it proves nothing about forwarding, VLANs, egress, DNS or
# packet behaviour. Those bnc only exist on s-nodus. SOPS secrets are also
# absent, so secret-consuming units (the Nebula PKI materialisation) fail
# closed here -- that is correct behaviour, not a bug.
#
# For the real thing use the nixos-shell-vm-manager path on s-nodus:
#   vm-update <vm> /home/deadbeef/github/nixos
#   systemctl start <vm>-vm.service
#
# Usage
#   ./boot-cobalt-new-under-tcg.sh <nixos-shell-output> [timeout-seconds]
#
# Example
#   VM=$(nix build --no-link --print-out-paths \
#          .#nixosConfigurations.s-router-cobalt-new.config.system.build.nixos-shell)
#   ./boot-cobalt-new-under-tcg.sh "$VM" 300
set -euo pipefail

vm_out="${1:-}"
timeout_s="${2:-300}"

if [ -z "${vm_out}" ]; then
  echo "usage: $0 <nixos-shell-output> [timeout-seconds]" >&2
  exit 2
fi

runner="$(ls "${vm_out}"/bin/run-*-vm 2>/dev/null | head -1)"
if [ -z "${runner}" ] || [ ! -e "${runner}" ]; then
  echo "error: no run-*-vm under ${vm_out}" >&2
  exit 1
fi
# `bin/run-*-vm` is a symlink to the real runner script; read through it.
runner_real="$(readlink -f "${runner}")"
[ -r "${runner_real}" ] || runner_real="${runner}"

# Recover the exact paths the generated runner would use, rather than
# guessing store paths.
sys="$(sed -n 's/.*NIXPKGS_QEMU_KERNEL[^:]*:-\([^}]*\)\/kernel}.*/\1/p' "${runner_real}" | head -1)"
if [ -z "${sys}" ]; then
  sys="$(grep -oE '/nix/store/[a-z0-9]+-nixos-system-[^/ ]+/init' "${runner_real}" | head -1 | xargs dirname)"
fi
initrd="$(grep -oE '/nix/store/[a-z0-9]+-initrd-linux-[^ "]+/initrd' "${runner_real}" | head -1)"
kernel="$(readlink -f "${sys}/kernel")"

for p in "${sys}/init" "${initrd}" "${kernel}"; do
  [ -e "${p}" ] || { echo "error: missing ${p}" >&2; exit 1; }
done

# The guest expects root on a disk labelled `nixos` plus a persisted
# /persist-state (the runner passes that as an extra 9p tag).
work="$(mktemp -d /tmp/vm-tcg.XXXXXXXXXX)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/shared" "${work}/xchg" "${work}/persist"

qemu_img="$(command -v qemu-img || true)"
mkfs="$(command -v mkfs.ext4 || true)"
for t in "${qemu_img}" "${mkfs}"; do
  [ -x "${t}" ] || { echo "error: need qemu-img and mkfs.ext4 on PATH (x86_64 builds)" >&2; exit 1; }
done

# Label the disk `nixos`: the initrd waits on /dev/disk/by-label/nixos.
"${qemu_img}" create -q -f raw "${work}/root.raw" 4G
"${mkfs}" -q -F -L nixos "${work}/root.raw" >/dev/null
"${qemu_img}" convert -q -f raw -O qcow2 "${work}/root.raw" "${work}/root.qcow2"
rm -f "${work}/root.raw"

echo "kernel : ${kernel}"
echo "initrd : ${initrd}"
echo "system : ${sys}"
echo "booting under TCG for up to ${timeout_s}s (login prompt is the success line)..."

exec timeout "${timeout_s}" qemu-system-aarch64 \
  -machine virt,gic-version=max -accel tcg -cpu max -smp 2 -m 1536 \
  -kernel "${kernel}" \
  -initrd "${initrd}" \
  -append "$(cat "${sys}/kernel-params") init=${sys}/init console=ttyAMA0" \
  -drive "file=${work}/root.qcow2,if=virtio,format=qcow2" \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -virtfs "local,path=/nix/store,security_model=none,readonly=on,mount_tag=nix-store" \
  -virtfs "local,path=${work}/shared,security_model=none,mount_tag=shared" \
  -virtfs "local,path=${work}/xchg,security_model=none,mount_tag=xchg" \
  -virtfs "local,path=${work}/persist,security_model=none,mount_tag=a450e1c198d7832105aba51788209f6" \
  -nographic -no-reboot
