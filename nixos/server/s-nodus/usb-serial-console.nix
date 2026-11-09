{ pkgs, ... }:

# Holtek HT42B534 "USB TO UART BRIDGE" (04d9:b534) on the board.
#
# This chip is a **CDC-ACM** device, not a usbserial one: Linux binds it with
# cdc_acm and exposes it as /dev/ttyACM0, and the by-id name ends in "-if00"
# (usbserial devices end in "-port0"). Reference: Holtek HT42B534-x datasheet
# and the BPI-R4 Pro forum thread for this exact chip ("Linux detects the
# onboard USB-UART correctly ... 04d9:b534 /dev/ttyACM0").
#
# Do NOT force it through usbserial. An earlier version of this module wrote
# "04d9 b534" into /sys/bus/usb-serial/drivers/generic/new_id; that steals the
# interface from cdc_acm and the kernel then rejects it:
#   usbserial_generic 1-5:1.2: device has no bulk endpoints
# leaving no tty at all. Loading cdc_acm is the whole fix.
#
# Cold boot worked but hotplug did not, which is the signature of USB runtime
# PM suspending hub ports; a re-plug then produces no uevent at all. Keep every
# device's power/control at "on" and autosuspend off.
{
  boot.kernelModules = [
    "cdc_acm"
    "usbcore"
  ];

  boot.kernelParams = [ "usbcore.autosuspend=-1" ];

  services.udev.extraRules = ''
    # Keep hub ports powered: without this a replug can stay invisible.
    ACTION=="add", SUBSYSTEM=="usb", ATTR{power/control}="on"

    # The tty appears as ttyACM<N> (CDC-ACM). Give it a stable name and start a
    # getty on it the moment it is added, so plugging the adapter in yields a
    # login instead of a dead device node.
    SUBSYSTEM=="tty", KERNEL=="ttyACM*", SYMLINK+="tty-serial-console", TAG+="systemd", ENV{SYSTEMD_WANTS}="serial-getty@%k.service"
  '';

  # Belt and braces: also pull the getty in via getty.target, in case the udev
  # tag races the device add. Restart keeps it retrying until the adapter is
  # present.
  systemd.services."serial-getty@ttyACM0" = {
    wantedBy = [ "getty.target" ];
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };
    restartIfChanged = false;
  };
}
