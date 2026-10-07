{ config, lib, ... }:

# Networking for s-nodus (BPI-R4 Pro 4E).
#
# Management/underlay is DHCP on lan5 (see ./cobalt-bridges.nix, which owns the
# networkd rules).  The board is NOT itself a router: the cobalt site router
# runs as the s-router-cobalt-new VM, and the only host-side network role is
# the L2 plumbing that feeds that VM's NICs (./cobalt-bridges.nix).
let
  cfg = config.local.bpiR4Pro;
in
{
  config = lib.mkIf cfg.enable {
    # The host does not route or NAT; the VM owns all routing/NAT behaviour.
    networking.nat.enable = false;
    networking.firewall.enable = false;

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 0;
      "net.ipv6.conf.all.forwarding" = 0;
    };
  };
}
