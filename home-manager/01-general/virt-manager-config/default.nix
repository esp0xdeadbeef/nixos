{ config, pkgs, ... }:

{
  dconf.settings = {
    "org/virt-manager/virt-manager" = {
      "xmleditor-enabled" = true;
      "show-status-icon" = true; # optional
    };
  };
}
