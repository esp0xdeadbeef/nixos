{ config, pkgs, ... }: 
{
  services.usbguard = {
    enable = true;
    implicitPolicyTarget = "block";  
    presentDevicePolicy = "apply-policy";
    presentControllerPolicy = "keep";  
    restoreControllerDeviceState = false;

    IPCAllowedUsers = [ "root" ];
    IPCAllowedGroups = [ "wheel" ];

    rules = ''
  allow id 1d6b:0002  # Linux Foundation 2.0 root hub
  allow id 1a40:0801  # Terminus Technology Inc. USB 2.0 Hub
  allow id 0c45:6748  # Microdia Integrated_Webcam_HD
  allow id 2109:0102  # VIA Labs, Inc. USB 2.0 BILLBOARD             
  allow id 27c6:63ac  # Shenzhen Goodix Technology Co.,Ltd. Goodix Fingerprint USB Device
  allow id 05e3:0610  # Genesys Logic, Inc. Hub
  allow id 8087:0033  # Intel Corp. AX211 Bluetooth
  allow id 1a40:0801  # Terminus Technology Inc. USB 2.0 Hub
  allow id 1d6b:0003  # Linux Foundation 3.0 root hub
  allow id 1d6b:0002  # Linux Foundation 2.0 root hub
  allow id 1d6b:0003  # Linux Foundation 3.0 root hub
  allow id 05e3:0626  # Genesys Logic, Inc. Hub
  allow id 067b:2773  # Prolific Technology, Inc. PL2773 SATAII bridge controller
  allow id 0bda:8153  # Realtek Semiconductor Corp. RTL8153 Gigabit Ethernet Adapter
  block
    '';
  };

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", TEST=="authorized", ATTR{authorized}="0", OWNER="usbguard", GROUP="wheel", MODE="0660"
  '';
}

