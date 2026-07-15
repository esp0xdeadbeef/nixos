{ lib }:

let
  coreTargetPath = [
    "control_plane_model"
    "data"
    "esp0xdeadbeef"
    "site-a"
    "runtimeTargets"
    "esp0xdeadbeef-site-a-core"
  ];

  isUnscopedPublicIngressAccept = rule:
    builtins.isAttrs rule
    && (rule.action or null) == "accept"
    && builtins.elem (rule.fromInterface or null) [
      "ppp0"
      "wan"
    ]
    && (rule.toInterface or null) == "ens3"
    && (rule.trafficType or null) == "any"
    && !(rule ? matches)
    && !(rule ? sourcePrefixes);

  patchControlPlane = cpm:
    let
      coreTarget = lib.attrByPath coreTargetPath null cpm;
      forwardingIntent = coreTarget.forwardingIntent or { };
      rules = forwardingIntent.rules or [ ];
      removedRules = builtins.filter isUnscopedPublicIngressAccept rules;
      patchedCoreTarget = coreTarget // {
        forwardingIntent = forwardingIntent // {
          rules = builtins.filter (rule: !isUnscopedPublicIngressAccept rule) rules;
        };
      };
    in
    if coreTarget == null then
      throw "s-router-prod Nebula ingress hotpatch: core runtime target is missing"
    else if builtins.length removedRules != 2 then
      throw "s-router-prod Nebula ingress hotpatch: expected exactly two unscoped ppp0/wan-to-ens3 accepts"
    else
      lib.recursiveUpdate cpm (lib.setAttrByPath coreTargetPath patchedCoreTarget);
in
{
  inherit patchControlPlane;

  nixosModule = { lib, ... }: {
    # Temporary until the production CPM/renderer chain materializes
    # publicIngressTupleAuthority as scoped core-owned DNAT and forwarding.
    containers.core.config.systemd.network.networks."10-ens3".routes = lib.mkAfter [
      {
        Destination = "192.168.3.10/32";
        Gateway = "10.10.0.7";
        GatewayOnLink = true;
      }
    ];

    # The DMZ has no general internet egress. Rewrite only the public-ingress
    # flow to the core loopback and route that single return address through
    # the VLAN 3 lane, so replies return to the owning conntrack entry without
    # introducing a DMZ default route.
    containers.policy.config.systemd.network.networks."10-upstream-vlan2".routes = lib.mkAfter [
      {
        Destination = "10.19.0.3/32";
        Gateway = "10.10.0.15";
        GatewayOnLink = true;
      }
    ];
    containers.downstream-selector.config.systemd.network.networks."10-policy-vlan3".routes =
      lib.mkAfter [
        {
          Destination = "10.19.0.3/32";
          Gateway = "10.10.0.11";
          GatewayOnLink = true;
        }
      ];
    containers.access-vlan3.config.systemd.network.networks."10-access-vlan3".routes = lib.mkAfter [
      {
        Destination = "10.19.0.3/32";
        Gateway = "10.10.0.3";
        GatewayOnLink = true;
      }
    ];

    containers.core.config.networking.nftables.ruleset = lib.mkAfter ''
      table ip s_router_prod_nebula_hotpatch {
        chain prerouting {
          type nat hook prerouting priority -101; policy accept;
          iifname "ppp0" udp dport 4242 counter dnat to 192.168.3.10:4242 comment "hotpatch-nebula-public-ingress-udp"
          iifname "ppp0" tcp dport 4242 counter dnat to 192.168.3.10:4242 comment "hotpatch-nebula-public-ingress-tcp"
        }

        chain postrouting {
          type nat hook postrouting priority 99; policy accept;
          iifname "ppp0" oifname "ens3" ct status dnat ip daddr 192.168.3.10 udp dport 4242 counter snat to 10.19.0.3 comment "hotpatch-nebula-public-ingress-snat-udp"
          iifname "ppp0" oifname "ens3" ct status dnat ip daddr 192.168.3.10 tcp dport 4242 counter snat to 10.19.0.3 comment "hotpatch-nebula-public-ingress-snat-tcp"
        }
      }

      add rule inet router forward iifname "ppp0" oifname "ens3" ct status dnat ip daddr 192.168.3.10 udp dport 4242 counter accept comment "hotpatch-nebula-forward-udp"
      add rule inet router forward iifname "ppp0" oifname "ens3" ct status dnat ip daddr 192.168.3.10 tcp dport 4242 counter accept comment "hotpatch-nebula-forward-tcp"
    '';
  };
}
