{ config, lib, ... }:

# Networking for s-nodus (BPI-R4 Pro 4E).
#
# Scope: every Ethernet port is a plain DHCP *client*. This is deliberately NOT
# a router yet -- no forwarding, no NAT, no firewall, no bridging of WAN/LAN.
# The box just gets addresses (one per port that has a link) from whatever
# DHCP server is upstream.
let
  cfg = config.local.bpiR4Pro;
in
{
  config = lib.mkIf cfg.enable {
    networking = {
      # DHCP on every interface (this is the NixOS default; stated for clarity).
      useDHCP = true;

      # No routing behaviour of any kind.
      nat.enable = false;
      firewall.enable = false;
    };

    # Belt-and-braces: make sure nothing is forwarding packets.
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 0;
      "net.ipv6.conf.all.forwarding" = 0;
    };
  };
}
