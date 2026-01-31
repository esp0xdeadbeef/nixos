{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    qbittorrent
  ];
}
