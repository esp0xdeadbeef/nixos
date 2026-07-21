{ ... }:

{
  # Temporary compatibility overrides for management VLAN 2 until the pinned
  # network-* stack materializes the site hostManagement contract itself.
  # Keep the host bridge on DHCPv4, but do not let management DHCP replace the
  # host's resolver configuration.
  systemd.network.networks."50-lan2" = {
    networkConfig.DHCP = "ipv4";
    dhcpV4Config.UseDNS = false;
  };
}
