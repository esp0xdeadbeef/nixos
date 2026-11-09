{ pkgs, lib, ... }:

# USB-serial console adapter on the board (Holtek "USB TO UART BRIDGE", 04d9:b534).
#
# Why this exists: the adapter enumerates but the kernel carries no id_table
# match for 04d9:b534, so no tty is created and nothing can open the console.
# Bind it explicitly, and scope the bind to INTERFACE 0: that is where the tty
# lives (the stable name is /dev/serial/by-id/usb-HOLTEK_USB_TO_UART_BRIDGE_0000-if00).
# A device-level match without bInterfaceNumber let udev pick whichever
# interface it saw first; on 2026-11-09 that was 1.2 and the kernel refused it:
#   usbserial_generic 1-5:1.2: device has no bulk endpoints
# so no /dev/ttyUSB* ever appeared.
let
  vendor = "04d9";
  product = "b534";
in
{
  boot.kernelModules = [ "usbserial" ];

  # The adapter enumerates on a COLD boot but not on hotplug. That is the
  # signature of USB runtime PM suspending the hub ports: a re-plug then never
  # produces a uevent (observed: `udevadm monitor --kernel` stayed silent while
  # the adapter was inserted, and lsusb showed only the hubs). Disable
  # autosuspend globally and force every USB device's power/control to "on" as
  # it is added.
  boot.kernelParams = [ "usbcore.autosuspend=-1" ];

  services.udev.extraRules = ''
    # Holtek USB TO UART BRIDGE: bind the generic usb-serial driver on the
    # interface that actually has the bulk endpoints, both at boot and hotplug.
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${vendor}", ATTR{idProduct}=="${product}", ATTR{bInterfaceNumber}=="00", \
      RUN+="${pkgs.kmod}/bin/modprobe usbserial", \
      RUN+="${pkgs.bash}/bin/sh -c 'echo ${vendor} ${product} > /sys/bus/usb-serial/drivers/generic/new_id 2>/dev/null || true'"

    # Bring a getty up on the USB-serial tty the moment it appears, so plugging
    # the adapter in yields a login instead of a dead device node. %k expands to
    # the kernel name (ttyUSB0, ...), so it works for any port number.
    SUBSYSTEM=="tty", KERNEL=="ttyUSB*", SYMLINK+="tty-serial-console", TAG+="systemd", ENV{SYSTEMD_WANTS}="serial-getty@%k.service"

    # Keep hub ports powered: without this a replug can stay invisible.
    ACTION=="add", SUBSYSTEM=="usb", ATTR{power/control}="on"
  '';

  # Belt and braces: also pull the getty in via getty.target for the common
  # first port, in case the udev tag races the device add. Restart keeps it
  # retrying until the adapter is present.
  systemd.services."serial-getty@ttyUSB0" = {
    wantedBy = [ "getty.target" ];
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };
    restartIfChanged = false;
  };
}
