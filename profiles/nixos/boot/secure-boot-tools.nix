{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.boot.lanzaboote.enable or false) {
    environment.systemPackages = [ pkgs.sbctl ];
  };
}
