# Laptop Thunderbolt docks

All laptop hosts import `profiles.nixos.laptop.default`. The profile enables:

- `services.hardware.bolt.enable = true`
- `services.fwupd.enable = true`

This is the default setup for Thunderbolt/USB4 docks such as the Lenovo
ThinkPad Thunderbolt 4 Dock.

## First use

Connect the dock, then inspect it:

```bash
boltctl list
```

If the dock is present but not authorized:

```bash
sudo boltctl authorize <uuid>
sudo boltctl enroll <uuid>
```

After enrollment, reconnect or power-cycle the dock and check for ethernet:

```bash
nmcli device status
ip -br link
```

## Troubleshooting

If the dock appears but ethernet does not, check whether the dock exposes an
ethernet device at all:

```bash
lsusb
lspci -nn | grep -Ei 'ethernet|network'
journalctl -b -k | grep -Ei 'thunderbolt|r815|r816|cdc_ether|usbnet|ethernet'
```

For Lenovo ThinkPad Thunderbolt 4 Dock / 40B0, common causes are:

- the dock is not authorized in `bolt`
- dock firmware is stale
- laptop BIOS/UEFI Thunderbolt settings block PCIe tunneling or user
  authorization
- the dock needs a full power-cycle after firmware or Secure Boot changes
- the wrong USB-C/TB port or cable is used

Firmware update flow:

```bash
fwupdmgr get-devices
fwupdmgr refresh
fwupdmgr get-updates
sudo fwupdmgr update
```

Do not use `Restore Factory Keys` in firmware when Secure Boot is already
managed by `sbctl`; that replaces the enrolled local keys.
