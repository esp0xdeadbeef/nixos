{ lib, pkgs, ... }:

{
  services.ollama = {
    enable = true;
    package = lib.mkDefault pkgs.unstable.ollama;
  };
}
