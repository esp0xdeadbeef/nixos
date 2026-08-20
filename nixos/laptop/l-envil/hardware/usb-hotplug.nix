{ config, lib, pkgs, ... }:

# Hotplug the cobalt AP radios into the s-router-cobalt VM via QMP when the
# USB device appears. This makes replugging recover without a VM restart:
# the host driver is unbound (so QEMU can claim the device) and a usb-host
# device is added over the vm-manager QMP socket.
let
  qmpSocket = "/run/nixos-shell-vm-manager/s-router-cobalt/qmp.sock";

  hotplug = pkgs.writeShellScript "qemu-usb-hotplug" ''
    set -eu
    vendorid="$1"
    productid="$2"
    id="$3"
    sock=${qmpSocket}

    # Unbind any host driver so QEMU's usb-host can claim the device.
    for dev in /sys/bus/usb/devices/*; do
      [ -r "$dev/idVendor" ] || continue
      [ -r "$dev/idProduct" ] || continue
      [ "$(cat "$dev/idVendor")" = "$vendorid" ] || continue
      [ "$(cat "$dev/idProduct")" = "$productid" ] || continue
      if [ -L "$dev/driver" ]; then
        drv=$(basename "$(readlink "$dev/driver")")
        [ "$drv" = "usbfs" ] || echo "$(basename "$dev")" > "/sys/bus/usb/drivers/$drv/unbind" 2>/dev/null || true
      fi
    done

    for _ in $(seq 1 60); do
      [ -S "$sock" ] && break
      sleep 1
    done
    [ -S "$sock" ] || exit 0

    printf '{"execute":"qmp_capabilities"}\n' | ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$sock" >/dev/null 2>&1 || true
    printf '{"execute":"device_add","arguments":{"driver":"usb-host","vendorid":"0x%s","productid":"0x%s","bus":"xhci.0","id":"%s"}}\n' \
      "$vendorid" "$productid" "$id" \
      | ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$sock" >/dev/null 2>&1 || true
  '';
in
{
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0846", ATTR{idProduct}=="9072", RUN+="${hotplug} 0846 9072 usb-nighthawk"
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="148f", ATTR{idProduct}=="3070", RUN+="${hotplug} 148f 3070 usb-alfa"
  '';
}
