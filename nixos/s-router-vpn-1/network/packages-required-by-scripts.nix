{ config, pkgs, ... }:

{
  # 1) Ensure cp/install/chmod are in $PATH
  environment.systemPackages = with pkgs; [
    sipcalc
  ];
}
