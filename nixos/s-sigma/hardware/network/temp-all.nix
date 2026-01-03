# file: ./network-clean.nix
{ config, pkgs, lib, ... }:


{

networking.interfaces.eno1.useDHCP = lib.mkDefault true;
networking.interfaces.eno2.useDHCP = lib.mkDefault true;
networking.interfaces.eno3.useDHCP = lib.mkDefault true;
networking.interfaces.eno4.useDHCP = lib.mkDefault true;
networking.interfaces.enp132s0f0.useDHCP = lib.mkDefault true;
networking.interfaces.enp132s0f1.useDHCP = lib.mkDefault true;
}

