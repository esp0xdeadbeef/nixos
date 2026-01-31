{ config, pkgs, ... }:
{
  # Get these flags by using:
  # dconf watch /
  dconf.settings = {
    "org/virt-manager/virt-manager" = {
      "xmleditor-enabled" = true;
      "system-tray" = true;
    };
  };
}
