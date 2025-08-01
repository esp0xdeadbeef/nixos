{ config, pkgs, ... }:
{
    # enable firmware updates:
    services.fwupd.enable = true;
}