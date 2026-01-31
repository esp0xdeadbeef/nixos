{
  pkgs,
  lib,
  helpers,
  args,
}:
{ config, ... }:

let
  lans = args.lans or [ ];

  wans = if args ? wans then args.wans else abort "mk-nixos-vlan: args.wans mandatory";

  wanTables = lib.imap0 (i: w: {
    name = w.name;
    iface = w.iface;
    mark = w.mark;
    tableId = 100 + i;

    ip4 = w.ip4;
    gw4 = w.gw4;

    ip6 = w.ip6;
    gw6 = w.gw6;

    acceptRA = w.acceptRA or false;
  }) wans;

  rpRules =
    (lib.imap0 (i: w: {
      FirewallMark = w.mark;
      Table = w.tableId;
      Priority = 1000 + i;
      Family = "ipv4";
    }) wanTables)
    ++ (lib.imap0 (i: w: {
      FirewallMark = w.mark;
      Table = w.tableId;
      Priority = 1000 + i;
      Family = "ipv6";
    }) wanTables);

in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  systemd.network.networks =
    # LANs
    (lib.listToAttrs (
      map (l: {
        name = "20-${l.name}-${l.iface}";
        value = {
          matchConfig.Name = l.iface;
          networkConfig = {
            Address = [
              l.ip4
              l.ip6
            ];
            DHCP = "no";
            IPv6Forwarding = true;
          };
          routingPolicyRules = rpRules;
        };
      }) lans
    ))
    //
      # WANs
      (lib.listToAttrs (
        lib.imap0 (i: w: {
          name = "10-wan-${w.name}-${w.iface}";
          value = {
            matchConfig.Name = w.iface;
            networkConfig = {
              Address = [
                w.ip4
                w.ip6
              ];
              DHCP = "no";
              IPv6AcceptRA = w.acceptRA;
              IPv6Forwarding = true;
            };

            # Policy routes
            routes = [
              {
                Destination = "0.0.0.0/0";
                Gateway = w.gw4;
                Table = w.tableId;
              }
              {
                Destination = "::/0";
                Gateway = w.gw6;
                Table = w.tableId;
              }
            ]
            # REAL default for router itself (WAN0 only)
            ++ lib.optionals (i == 0) [
              {
                Destination = "0.0.0.0/0";
                Gateway = w.gw4;
              }
              {
                Destination = "::/0";
                Gateway = w.gw6;
              }
            ];

            routingPolicyRules = rpRules;
          };
        }) wanTables
      ));
}
