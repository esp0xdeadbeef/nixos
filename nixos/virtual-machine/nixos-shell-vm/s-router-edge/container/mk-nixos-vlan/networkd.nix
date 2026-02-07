# mk-nixos-vlan/networkd.nix
{
  config,
  pkgs,
  lib,
  args,
  ...
}:

let
  helpers = import ./helpers.nix { inherit lib; };

  lans = args.lans or [ ];
  transits = args.transits or [ ];

  wans =
    assert args ? wans;
    args.wans;

  allIfaces = lans ++ transits;

  #
  # Normalize WAN tables
  #
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

  #
  # INTERNAL BYPASS RULES (STRICT)
  #
  # Policy:
  # - ONLY internal ULAs may bypass PBR
  # - NEVER bypass for WAN-learned prefixes
  # - Transit ULAs are allowed
  #
  internalBypassRules =
    (lib.concatMap (
      l:
      lib.optionals (l ? ip4) [
        {
          Family = "ipv4";
          To = "${helpers.ipv4Base3 l.ip4}.0/24";
          Table = 254; # main
          Priority = 500;
        }
      ]
    ) allIfaces)
    ++ (lib.concatMap (
      l:
      lib.optionals (l ? ip6 && lib.hasPrefix "fd" l.ip6) [
        {
          Family = "ipv6";
          To = l.ip6;
          Table = 254; # main
          Priority = 500;
        }
      ]
    ) allIfaces);

  #
  # POLICY ROUTING RULES
  #
  rpRules =
    internalBypassRules
    ++ lib.imap0 (i: w: {
      FirewallMark = w.mark;
      Table = w.tableId;
      Priority = 1000 + i;
      Family = "ipv4";
    }) wanTables
    ++ lib.imap0 (i: w: {
      FirewallMark = w.mark;
      Table = w.tableId;
      Priority = 1000 + i;
      Family = "ipv6";
    }) wanTables;

in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  #
  # Router sysctls
  #
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  #
  # LAN + TRANSIT interfaces
  #
  systemd.network.networks =
    (lib.listToAttrs (
      map (l: {
        name = "20-${l.name}";
        value = {
          matchConfig.Name = l.iface;

          networkConfig = {
            Address = [
              l.ip4
              l.ip6
            ];
            DHCP = "no";
            IPv6AcceptRA = false;
            IPv6Forwarding = true;
          };

          routingPolicyRules = rpRules;
        };
      }) allIfaces
    ))
    //
      #
      # WAN interfaces
      #
      (lib.listToAttrs (
        lib.imap0 (i: w: {
          name = "10-wan-${w.name}";
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
