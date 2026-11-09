{ pkgs, ... }:

# Holtek "USB TO UART BRIDGE" (04d9:b534) — the serial console adapter.
#
# Measured on this host before the fix: the adapter ENUMERATES but no serial
# driver ever binds it.
#
#   kernel: usb 1-5: New USB device found, idVendor=04d9, idProduct=b534
#   lsusb:  Bus 001 Device 024: ID 04d9:b534 Holtek Semiconductor, Inc.
#           product=USB TO UART BRIDGE  manufacturer=HOLTEK
#   /dev/ttyUSB*: none, and "ttyUSB" appears 0 times across two boots
#
# The kernel carries no id_table match for 04d9:b534, so nothing creates a tty
# and the console is unavailable — no matter how the adapter is plugged in.
# The generic usbserial driver has to be loaded and told to claim the IDs.
#
# Two parts, both required:
#   1. load usbserial at boot so udev can bind against it on hotplug;
#   2. on USB add, attach the generic driver to 04d9:b534.
#
# Use /dev/serial/by-id/... to open it: ttyUSB numbering depends on
# enumeration order.
let
  holtekVendor = "04d9";
  holtekProduct = "b534";
in
{
  boot.kernelModules = [
    "usbserial"
    "usb_serial_simple"
  ];

  # `RUN+=` runs without a PATH, so modprobe and sh are absolute.
  services.udev.extraRules = ''
    # Holtek USB TO UART BRIDGE: bind the generic usb-serial driver, both when
    # it is present at boot and when it is plugged in later.
    # Scope the bind to interface 0: the console tty lives there (the by-id
    # name ends in -if00). A device-level match without ATTR{bInterfaceNumber}
    # let udev pick whichever interface it processed first -- on 2026-11-09 it
    # bound usbserial_generic to 1.2 and the kernel refused it:
    #   usbserial_generic 1-5:1.2: device has no bulk endpoints
    # so no /dev/ttyUSB* appeared and the only way back was a cold boot.
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${holtekVendor}", ATTR{idProduct}=="${holtekProduct}", ATTR{bInterfaceNumber}=="00", \
      RUN+="${pkgs.kmod}/bin/modprobe usbserial", \
      RUN+="${pkgs.bash}/bin/sh -c 'echo ${holtekVendor} ${holtekProduct} > /sys/bus/usb-serial/drivers/generic/new_id 2>/dev/null || true'"

    # Keep a stable name for anything that opens the console by path.
    SUBSYSTEM=="tty", KERNEL=="ttyUSB*", SYMLINK+="tty-serial-console", TAG+="systemd"
  '';
}
