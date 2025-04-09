{
  config,
  pkgs,
  lib,
  ...
}:

{
  # nmcli connection modify Wired\ connection\ 1 ipv4.route-metric 99999 ipv6.route-metric 50
  networking.networkmanager.enable = true;

  # Let NM manage ens18 (management NIC)
  networking.networkmanager.unmanaged = [ "phys0" ];
}
