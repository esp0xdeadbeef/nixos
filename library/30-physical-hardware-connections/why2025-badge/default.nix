{ config, pkgs, inputs, outputs, ... }:
{

  users.users.deadbeef.extraGroups = [ "dialout" "uucp" ];
  

  services.udev.extraRules = ''
    # Espressif WebUSB + Serial
    SUBSYSTEM=="tty", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="1001", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="303a", ATTR{idProduct}=="1001", MODE="0666"

    # CH341 UART fallback (ttyUSB0)
    SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7522", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", ATTR{idProduct}=="7522", MODE="0666"

    # Just all the tty shit:
    SUBSYSTEM=="tty", GROUP="dialout", MODE="0660"
  '';

}
