{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    jython
    python3
    python3.pkgs.pip
    python3.pkgs.evdev
    python3.pkgs.pygraphviz
  ];
}