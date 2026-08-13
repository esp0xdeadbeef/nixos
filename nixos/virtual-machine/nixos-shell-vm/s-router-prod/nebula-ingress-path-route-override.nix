{ lib, ... }:
let
  routeTable = 14242;
  rulePriority = 900;
in
{
  # TEMPORARY NETWORK-* COMPATIBILITY OVERRIDE.
  #
  # The renderer copies the core-owned Nebula SNAT return address into
  # multiple tenant policy tables. Policy then rejects the forward packet
  # during source validation because the equal-prefix route can resolve over
  # another tenant lane. Give this ingress relation a dedicated symmetric
  # route table so policy remains a pure router and all NAT stays in core.
  #
  # Remove this entire file, its import, warning, and parity assertion once
  # network-* emits relation-bound forward and return policy routes for public
  # ingress without copying the SNAT return route across tenant lanes.
  containers.policy.config.systemd.network.networks = {
    "10-upstream-vlan3" = {
      routes = lib.mkAfter [
        {
          Destination = "10.19.0.4/32";
          Gateway = "10.10.0.21";
          GatewayOnLink = true;
          Table = routeTable;
        }
      ];

      routingPolicyRules = lib.mkAfter [
        {
          Family = "ipv4";
          From = "10.19.0.4/32";
          IncomingInterface = "upstream-vlan3";
          Priority = rulePriority;
          Table = routeTable;
          To = "192.168.3.10/32";
        }
      ];
    };

    "10-down-vlan3" = {
      routes = lib.mkAfter [
        {
          Destination = "192.168.3.10/32";
          Gateway = "10.10.0.10";
          GatewayOnLink = true;
          Table = routeTable;
        }
      ];

      routingPolicyRules = lib.mkAfter [
        {
          Family = "ipv4";
          From = "192.168.3.10/32";
          IncomingInterface = "down-vlan3";
          Priority = rulePriority;
          Table = routeTable;
          To = "10.19.0.4/32";
        }
      ];
    };
  };
}
