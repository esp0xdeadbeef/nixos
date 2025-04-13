{ config, pkgs, ... }:
{
  #############################
  # Bluetooth enabled
  #############################
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
}
