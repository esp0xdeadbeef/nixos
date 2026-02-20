{ pkgs, lib, ... }:
{

boot.kernel.sysctl = {
  "net.ipv4.ip_forward" = 1;
  "net.ipv6.conf.all.forwarding" = 1;

  # routers ignore RA unless explicitly enabled
  "net.ipv6.conf.all.accept_ra" = 0;
  "net.ipv6.conf.wan.accept_ra" = 2;
};
}
