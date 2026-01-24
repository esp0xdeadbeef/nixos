{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    jq
    gron
    unzip
  ];
}
