{ lib, ... }:

{
  system.autoUpgrade = {
    operation = lib.mkForce "boot";
    allowReboot = lib.mkForce true;
  };
}
