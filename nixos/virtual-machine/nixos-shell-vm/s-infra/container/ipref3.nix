{ config, pkgs, ... }:

{
  services.iperf3.enable = true;
  services.iperf3.openFirewall = true;
}
