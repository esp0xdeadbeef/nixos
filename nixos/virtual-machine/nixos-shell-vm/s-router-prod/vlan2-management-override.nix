{ lib, ... }:

{
  # Temporary compatibility overrides for management VLAN 2 until the pinned
  # network-* stack materializes the site hostManagement contract itself.
  # Keep the host bridge on DHCPv4, but do not let management DHCP replace the
  # host's resolver configuration.
  systemd.network.networks."50-lan2" = {
    networkConfig.DHCP = "ipv4";
    dhcpV4Config.UseDNS = false;
  };

  # The pinned renderer sends VLAN 2 -> VLAN 3 directly to access-vlan3 while
  # the return path traverses policy. Select the existing VLAN 2 policy table
  # first so the stateful return rule sees both directions.
  containers.downstream-selector.config.systemd.network.networks."10-access-vlan2".routingPolicyRules =
    lib.mkAfter [
      {
        Family = "ipv4";
        From = "192.168.1.0/24";
        To = "192.168.3.0/24";
        IncomingInterface = "access-vlan2";
        Priority = 900;
        Table = 1004;
      }
    ];

  # The policy selector above deliberately sends VLAN 2 -> VLAN 3 through the
  # policy router. The renderer still emits the service allow only for the
  # direct access-vlan2 -> access-vlan3 path, so permit the narrowly scoped
  # post-policy handoff until network-* models this traversal end to end.
  containers.downstream-selector.config.networking.nftables.ruleset = lib.mkAfter ''
    add rule inet router forward iifname "policy-vlan3" oifname "access-vlan3" ip saddr 192.168.1.0/24 ip daddr 192.168.3.10 ip protocol icmp counter accept comment "s-router-prod-vlan2-nebula-icmp-post-policy"
  '';
}
