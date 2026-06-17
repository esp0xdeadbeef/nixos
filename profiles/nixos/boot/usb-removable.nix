{ lib, pkgs, ... }:

let
  isX86 = pkgs.stdenv.hostPlatform.isx86;

  commonUsbStorageModules = [
    "usbcore"
    "usb_common"
    "usb_storage"
    "uas"
    "usbhid"
    "hid_generic"
    "xhci_pci"
    "xhci_hcd"
    "scsi_mod"
    "sd_mod"
    "sr_mod"
  ];

  legacyX86UsbControllerModules = [
    "uhci_hcd"
    "ohci_hcd"
    "ehci_pci"
    "ehci_hcd"
  ];
in
{
  hardware.enableAllFirmware = true;

  boot.initrd.availableKernelModules = lib.mkAfter (
    commonUsbStorageModules ++ lib.optionals isX86 legacyX86UsbControllerModules
  );
}
