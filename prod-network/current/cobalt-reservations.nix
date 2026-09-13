# Cobalt static client reservations.
#
# Each handle is also the per-device secret filename
# (secrets/devices/<handle>.age) and the stable endpoint handle. The host
# offset is the device's network-local id: the same offset resolves against
# each scope's own served prefix, so one device may keep ".10" while moving
# between VLAN 2 and VLAN 8.
{
  l-portal-usb = {
    hostname = "l-portal";
    scopes = {
      cobalt-clients = 10;
      cobalt-iot = 10;
    };
  };
}
