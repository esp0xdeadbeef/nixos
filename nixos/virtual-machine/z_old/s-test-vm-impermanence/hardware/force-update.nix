{ config, lib, ... }:

{
  system.autoUpgrade = {
    operation = lib.mkForce "switch";
    allowReboot = lib.mkForce true;
  };
}
