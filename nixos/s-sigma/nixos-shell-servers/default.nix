{ config, lib, pkgs, self, ... }:

lib.mkIf (!config.system.build.installing) {
  imports = [
    ./servers.nix
  ];
}

