{ config, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.OVMF
  ];
}

