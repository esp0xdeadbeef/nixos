{ config, lib, pkgs, ... }:

{
  # 1.  Ensure the driver is always in the kernel
  boot.kernelModules = [ "tun" ];

  # 2.  Make /dev/net/tun exist and stay world‑rw
  services.udev.extraRules = ''
    KERNEL=="tun", MODE="0666", OPTIONS+="static_node=net/tun"
  '';

}