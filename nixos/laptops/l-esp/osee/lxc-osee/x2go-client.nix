{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    x2goclient # the X2Go GUI client
  ];
}
