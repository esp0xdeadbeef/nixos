# file: ./network-clean.nix
{
  config,
  pkgs,
  lib,
  ...
}:

{

  # mgmt (direct - no vlan tag):
  networking.interfaces.eno1.useDHCP = lib.mkDefault true;
  # trunk (VMBR4):
  networking.interfaces.eno2.useDHCP = lib.mkDefault true;

  # Not used because wrong SFP modules (can be placed though):
  networking.interfaces.eno3.useDHCP = lib.mkDefault false;
  networking.interfaces.eno4.useDHCP = lib.mkDefault false;

  # old VMBR2 bridge (not used anymore):
  networking.interfaces.enp132s0f0.useDHCP = lib.mkDefault false;

  # VMBR1 (ISP):
  networking.interfaces.enp132s0f1.useDHCP = lib.mkDefault true;
}
