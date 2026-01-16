{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
{
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/persist/etc/secureboot";
  };
}