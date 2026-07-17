{ config
, lib
, pkgs
, ...
}:
let
  delegatedPrefixFile = config.sops.secrets.subnet-ipv6-vlan3.path;
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
    };

    networking.nftables.ruleset = lib.mkAfter ''
      add set inet router ${nebulaIpv6SetName} { type ipv6_addr; }
      add rule inet router input iifname "ppp0" ip6 saddr fe80::/10 udp sport 547 udp dport 546 counter accept comment "s-router-prod-dhcpv6-replies"
      add rule inet router forward iifname "ppp0" oifname "ens3" ip6 daddr @${nebulaIpv6SetName} udp dport 4242 counter accept comment "s-router-prod-nebula6-forward-udp"
      add rule inet router forward iifname "ppp0" oifname "ens3" ip6 daddr @${nebulaIpv6SetName} tcp dport 4242 counter accept comment "s-router-prod-nebula6-forward-tcp"
    '';
  };

  containers.upstream-selector.config = {
    systemd.services.s-router-prod-nebula-ipv6-firewall = nebulaIpv6SetService;

    networking.nftables.ruleset = lib.mkAfter ''
      add set inet router ${nebulaIpv6SetName} { type ipv6_addr; }
      add rule inet router forward iifname "core" oifname "policy-vlan2" ip daddr 192.168.3.10 udp dport 4242 counter accept comment "s-router-prod-nebula4-forward-udp"
      add rule inet router forward iifname "core" oifname "policy-vlan2" ip daddr 192.168.3.10 tcp dport 4242 counter accept comment "s-router-prod-nebula4-forward-tcp"
      add rule inet router forward iifname "core" oifname "policy-vlan2" ip6 daddr @${nebulaIpv6SetName} udp dport 4242 counter accept comment "s-router-prod-nebula6-forward-udp"
      add rule inet router forward iifname "core" oifname "policy-vlan2" ip6 daddr @${nebulaIpv6SetName} tcp dport 4242 counter accept comment "s-router-prod-nebula6-forward-tcp"
    '';
  };
}
