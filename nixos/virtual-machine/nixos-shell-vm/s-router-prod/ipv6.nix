{ config
, lib
, pkgs
, sRouterProdRendererCapabilities
, ...
}:
let
  rendererHasTenantIpv6Routes =
    sRouterProdRendererCapabilities.delegatedPrefixTenantRoutes or false;
  needsExactTenantRouteCompatibility = !rendererHasTenantIpv6Routes;
  delegatedPrefixes = {
    vlan2 = {
      sourceFile = config.sops.secrets.subnet-ipv6-vlan2.path;
      slot = 2;
    };
    vlan3 = {
      sourceFile = config.sops.secrets.subnet-ipv6-vlan3.path;
      slot = 3;
    };
    vlan7 = {
      sourceFile = config.sops.secrets.subnet-ipv6-vlan7.path;
      slot = 7;
    };
  };
  delegatedPrefixFile = delegatedPrefixes.vlan3.sourceFile;

  derivePrefix = pkgs.writeShellScript "s-router-prod-derive-ipv6-prefix" ''
    set -euo pipefail

    ${pkgs.python3}/bin/python3 - "$1" "$2" <<'PY'
    import ipaddress
    import pathlib
    import sys

    delegated = ipaddress.IPv6Network(pathlib.Path(sys.argv[1]).read_text().strip(), strict=True)
    if delegated.prefixlen != 48:
        raise ValueError(f"expected IPv6 /48, got {delegated}")

    slot = int(sys.argv[2])
    print(ipaddress.IPv6Network((int(delegated.network_address) + (slot << 64), 64)))
    PY
  '';

  routeCommand = route: table:
    let
      prefix = delegatedPrefixes.${route.tenant};
      tableArgument = lib.optionalString (table != null) "table ${toString table} ";
    in
    ''
      prefix="$(${derivePrefix} ${lib.escapeShellArg prefix.sourceFile} ${toString prefix.slot})"
      ${pkgs.iproute2}/bin/ip -6 route replace ${tableArgument}"$prefix" \
        via ${lib.escapeShellArg route.gateway} \
        dev ${lib.escapeShellArg route.interface} \
        proto static onlink
    '';

  exactRouteService = routes: {
    description = "Install exact routed IPv6 tenant prefixes";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-networkd.service" ];
    wants = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "1s";
    };
    script = ''
      set -euo pipefail

      ${lib.concatMapStringsSep "\n" (route:
        lib.concatMapStringsSep "\n" (routeCommand route) route.tables
      ) routes}
    '';
  };

  nebulaIpv6SetName = "s_router_prod_nebula6";
  loadNebulaIpv6Set = pkgs.writeShellScript "s-router-prod-load-nebula-ipv6-set" ''
    set -euo pipefail

    address="$(${pkgs.python3}/bin/python3 - ${lib.escapeShellArg delegatedPrefixFile} <<'PY'
    import ipaddress
    import pathlib
    import sys

    delegated = ipaddress.IPv6Network(pathlib.Path(sys.argv[1]).read_text().strip(), strict=True)
    if delegated.prefixlen != 48:
        raise SystemExit(f"{sys.argv[1]} must contain an IPv6 /48")

    prefix = ipaddress.IPv6Network((int(delegated.network_address) + (3 << 64), 64))
    suffix = int(ipaddress.IPv6Address("::1337:dead:beef"))
    print(ipaddress.IPv6Address(int(prefix.network_address) + suffix))
    PY
    )"

    ${pkgs.nftables}/bin/nft -f - <<EOF
    flush set inet router ${nebulaIpv6SetName}
    add element inet router ${nebulaIpv6SetName} { $address }
    EOF
  '';

  nebulaIpv6SetService = {
    description = "Load the runtime Nebula GUA into nftables";
    wantedBy = [ "multi-user.target" ];
    after = [ "nftables.service" ];
    requires = [ "nftables.service" ];
    partOf = [ "nftables.service" ];
    unitConfig.ReloadPropagatedFrom = [ "nftables.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = loadNebulaIpv6Set;
      ExecReload = loadNebulaIpv6Set;
    };
  };
in
{
  warnings = lib.optional needsExactTenantRouteCompatibility
    "s-router-prod compatibility override: the pinned renderer routes the delegated /48 directly instead of deriving each slot-specific tenant /64; local exact /64 route services remain active";

  containers.core.config = {
    environment.etc."s-router-prod/dhcpcd-ipv6.conf".text = ''
      duid
      persistent
      nohook resolv.conf
      noipv6rs
      noipv4
      ipv6only

      interface ppp0
        iaid 1
        ia_pd 1
    '';

    systemd.services = {
      pppd-s88-pppoe-client-wan.preStart = lib.mkAfter ''
        printf '%s\n' defaultroute6 >> /run/pppd/s88-pppoe-client-wan.options
      '';

      dhcpcd-ipv6 = {
        description = "Acquire the IPv6 prefix delegation on ppp0";
        wantedBy = [ "multi-user.target" ];
        after = [ "pppd-s88-pppoe-client-wan.service" ];
        wants = [ "pppd-s88-pppoe-client-wan.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.dhcpcd}/bin/dhcpcd -6 -d -B -f /etc/s-router-prod/dhcpcd-ipv6.conf ppp0";
          Restart = "always";
          RestartSec = "2s";
        };
      };

      s-router-prod-nebula-ipv6-firewall = nebulaIpv6SetService;
    } // lib.optionalAttrs needsExactTenantRouteCompatibility {
      s-router-prod-ipv6-routes = exactRouteService [
        {
          tenant = "vlan2";
          interface = "ens3";
          gateway = "fd42:dead:beef:1000::7";
          tables = [ null ];
        }
        {
          tenant = "vlan3";
          interface = "ens3";
          gateway = "fd42:dead:beef:1000::7";
          tables = [ null ];
        }
        {
          tenant = "vlan7";
          interface = "ens3";
          gateway = "fd42:dead:beef:1000::7";
          tables = [ null ];
        }
      ];
    };

    networking.nftables.ruleset = lib.mkAfter ''
      add set inet router ${nebulaIpv6SetName} { type ipv6_addr; }
      add rule inet router input iifname "ppp0" ip6 saddr fe80::/10 udp sport 547 udp dport 546 counter accept comment "s-router-prod-dhcpv6-replies"
      add rule inet router forward iifname "ppp0" oifname "ens3" ip6 daddr @${nebulaIpv6SetName} udp dport 4242 counter accept comment "s-router-prod-nebula6-forward-udp"
      add rule inet router forward iifname "ppp0" oifname "ens3" ip6 daddr @${nebulaIpv6SetName} tcp dport 4242 counter accept comment "s-router-prod-nebula6-forward-tcp"
    '';
  };

  containers.upstream-selector.config = {
    systemd.services = {
      s-router-prod-nebula-ipv6-firewall = nebulaIpv6SetService;
    } // lib.optionalAttrs needsExactTenantRouteCompatibility {
      s-router-prod-ipv6-routes = exactRouteService [
        {
          tenant = "vlan2";
          interface = "policy-vlan2";
          gateway = "fd42:dead:beef:1000::e";
          tables = [ null 1001 1003 ];
        }
        {
          tenant = "vlan3";
          interface = "policy-vlan2";
          gateway = "fd42:dead:beef:1000::e";
          tables = [ null ];
        }
        {
          tenant = "vlan7";
          interface = "policy";
          gateway = "fd42:dead:beef:1000::10";
          tables = [ null 1001 1002 ];
        }
      ];
    };

    networking.nftables.ruleset = lib.mkAfter ''
      add set inet router ${nebulaIpv6SetName} { type ipv6_addr; }
      add rule inet router forward iifname "core" oifname "policy-vlan2" ip daddr 192.168.3.10 udp dport 4242 counter accept comment "s-router-prod-nebula4-forward-udp"
      add rule inet router forward iifname "core" oifname "policy-vlan2" ip daddr 192.168.3.10 tcp dport 4242 counter accept comment "s-router-prod-nebula4-forward-tcp"
      add rule inet router forward iifname "core" oifname "policy-vlan2" ip6 daddr @${nebulaIpv6SetName} udp dport 4242 counter accept comment "s-router-prod-nebula6-forward-udp"
      add rule inet router forward iifname "core" oifname "policy-vlan2" ip6 daddr @${nebulaIpv6SetName} tcp dport 4242 counter accept comment "s-router-prod-nebula6-forward-tcp"
    '';
  };

  containers.policy.config = lib.mkIf needsExactTenantRouteCompatibility {
    systemd.services.s-router-prod-ipv6-routes = exactRouteService [
      {
        tenant = "vlan2";
        interface = "down-vlan2";
        gateway = "fd42:dead:beef:1000::8";
        tables = [ null 1001 1002 1004 ];
      }
      {
        tenant = "vlan3";
        interface = "down-vlan3";
        gateway = "fd42:dead:beef:1000::a";
        tables = [ null 1003 ];
      }
      {
        tenant = "vlan7";
        interface = "downstr-vlan7";
        gateway = "fd42:dead:beef:1000::c";
        tables = [ null 1001 1002 1005 ];
      }
    ];
  };

  containers.downstream-selector.config = lib.mkIf needsExactTenantRouteCompatibility {
    systemd.services.s-router-prod-ipv6-routes = exactRouteService [
      {
        tenant = "vlan2";
        interface = "access-vlan2";
        gateway = "fd42:dead:beef:1000::";
        tables = [ null 1001 1002 1004 ];
      }
      {
        tenant = "vlan3";
        interface = "access-vlan3";
        gateway = "fd42:dead:beef:1000::2";
        tables = [ null 1002 1005 ];
      }
      {
        tenant = "vlan7";
        interface = "access-vlan7";
        gateway = "fd42:dead:beef:1000::4";
        tables = [ null 1003 1006 ];
      }
    ];
  };
}
