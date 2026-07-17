{ config, lib, outPath, ... }:

let
  expectedQemuNetworkingOptions = [
    "-nic none"
    "-nic bridge,br=vmbr4,mac=52:54:00:12:34:56,model=virtio-net-pci"
    "-nic bridge,br=vmbr1,mac=52:54:00:12:34:57,model=virtio-net-pci"
  ];

  expectedContainers = [
    "access-vlan3"
    "access-vlan2"
    "access-vlan7"
    "core"
    "downstream-selector"
    "policy"
    "upstream-selector"
  ];

  netdevBridgeNames =
    lib.pipe (config.systemd.network.netdevs or { }) [
      builtins.attrValues
      (builtins.map (netdev: netdev.netdevConfig or { }))
      (builtins.filter (netdevConfig: (netdevConfig.Kind or null) == "bridge"))
      (builtins.map (netdevConfig: netdevConfig.Name or null))
      (builtins.filter (name: name != null))
    ];

  containerNames = builtins.attrNames (config.containers or { });

  coreExtraVethBridges =
    lib.pipe (config.containers.core.extraVeths or { }) [
      builtins.attrValues
      (builtins.map (veth: veth.hostBridge or null))
      (builtins.filter (bridge: bridge != null))
    ];

  hasExpectedContainers =
    builtins.all (name: builtins.elem name containerNames) expectedContainers
    && !(builtins.hasAttr "external-isp" (config.containers or { }));

  servicesFor =
    containerName:
      config.containers.${containerName}.config.systemd.services or { };

  hasRenderedService =
    containerName: stem:
    builtins.any
      (name: builtins.match "${stem}-[0-9]+" name != null)
      (builtins.attrNames (servicesFor containerName));

  requiredRendererIpv6ServiceStems = {
    core = [
      "s88-delegated-prefix-route-ens3"
    ];
    upstream-selector = [
      "s88-delegated-prefix-route-policy"
      "s88-delegated-prefix-route-policy-vlan2"
      "s88-delegated-prefix-route-policy-vlan3"
      "s88-delegated-prefix-policy-route-policy-1001"
      "s88-delegated-prefix-policy-route-policy-1002"
      "s88-delegated-prefix-policy-route-policy-vlan2-1001"
      "s88-delegated-prefix-policy-route-policy-vlan2-1003"
      "s88-delegated-prefix-policy-route-policy-vlan3-1001"
      "s88-delegated-prefix-policy-route-policy-vlan3-1004"
    ];
    policy = [
      "s88-delegated-prefix-route-down-vlan2"
      "s88-delegated-prefix-route-down-vlan3"
      "s88-delegated-prefix-route-downstr-vlan7"
      "s88-delegated-prefix-policy-route-down-vlan2-1001"
      "s88-delegated-prefix-policy-route-down-vlan2-1002"
      "s88-delegated-prefix-policy-route-down-vlan2-1004"
      "s88-delegated-prefix-policy-route-down-vlan3-1001"
      "s88-delegated-prefix-policy-route-down-vlan3-1002"
      "s88-delegated-prefix-policy-route-down-vlan3-1003"
      "s88-delegated-prefix-policy-route-down-vlan3-1005"
      "s88-delegated-prefix-policy-route-downstr-vlan7-1001"
      "s88-delegated-prefix-policy-route-downstr-vlan7-1002"
      "s88-delegated-prefix-policy-route-downstr-vlan7-1006"
    ];
    downstream-selector = [
      "s88-delegated-prefix-route-access-vlan2"
      "s88-delegated-prefix-route-access-vlan3"
      "s88-delegated-prefix-route-access-vlan7"
      "s88-delegated-prefix-policy-route-access-vlan2-1001"
      "s88-delegated-prefix-policy-route-access-vlan2-1002"
      "s88-delegated-prefix-policy-route-access-vlan2-1004"
      "s88-delegated-prefix-policy-route-access-vlan3-1002"
      "s88-delegated-prefix-policy-route-access-vlan3-1005"
      "s88-delegated-prefix-policy-route-access-vlan7-1003"
      "s88-delegated-prefix-policy-route-access-vlan7-1006"
    ];
  };

  hasRendererNativeIpv6Routes =
    builtins.all
      (containerName:
        builtins.all
          (hasRenderedService containerName)
          requiredRendererIpv6ServiceStems.${containerName})
      (builtins.attrNames requiredRendererIpv6ServiceStems)
    && builtins.all
      (containerName:
        builtins.any
          (lib.hasPrefix "s88-delegated-prefix-route-")
          (builtins.attrNames (servicesFor containerName)))
      expectedContainers;

  tenantIpv6RouteContainers = [
    "core"
    "upstream-selector"
    "policy"
    "downstream-selector"
  ];

  hasNoExactTenantIpv6RouteCompatibility =
    builtins.all
      (containerName: !(builtins.hasAttr "s-router-prod-ipv6-routes" (servicesFor containerName)))
      tenantIpv6RouteContainers;

  expectedDnsForwarders = [
    "1.1.1.1"
    "9.9.9.9"
  ];

  unboundForwardersFor =
    containerName:
    let
      settings = config.containers.${containerName}.config.services.unbound.settings or { };
      forwardZones = settings."forward-zone" or [ ];
    in
    lib.unique (lib.flatten (map (zone: zone."forward-addr" or [ ]) forwardZones));

  unboundServerFor =
    containerName:
      config.containers.${containerName}.config.services.unbound.settings.server or { };

  hasVlan2RuntimeLocalDns =
    let
      server = unboundServerFor "access-vlan2";
    in
    builtins.elem "lan. static" (server.local-zone or [ ])
    && builtins.elem "1.168.192.in-addr.arpa. static" (server.local-zone or [ ])
    && builtins.elem "/run/unbound/s-router-prod-vlan2-local.conf" (server.include or [ ])
    && builtins.hasAttr "gen-s-router-prod-vlan2-unbound-local-data"
      config.containers.access-vlan2.config.systemd.services;

  hasVlan3LocalDns =
    let
      server = unboundServerFor "access-vlan3";
    in
    builtins.elem "lan. static" (server."local-zone" or [ ])
    && builtins.elem ''"s-nebula-container.lan. IN A 192.168.3.10"'' (server."local-data" or [ ]);

  hasNoVlan3DnsUpstream =
    unboundForwardersFor "access-vlan3" == [ ]
    && !(lib.hasInfix "nft add rule inet router output" (dnsNftScriptFor "access-vlan3"));

  dnsNftScriptFor =
    containerName:
      config.containers.${containerName}.config.systemd.services.nft-allow-dns-service.script or "";

  dnsEgressFragments = {
    access-vlan2 = [
      "ip saddr 192.168.1.1 ip daddr 1.1.1.1 udp dport 53"
      "ip saddr 192.168.1.1 ip daddr 9.9.9.9 udp dport 53"
      "ip saddr 192.168.1.1 ip daddr 1.1.1.1 tcp dport 53"
      "ip saddr 192.168.1.1 ip daddr 9.9.9.9 tcp dport 53"
    ];

    access-vlan7 = [
      "ip saddr 192.168.2.1 ip daddr 1.1.1.1 udp dport 53"
      "ip saddr 192.168.2.1 ip daddr 9.9.9.9 udp dport 53"
      "ip saddr 192.168.2.1 ip daddr 1.1.1.1 tcp dport 53"
      "ip saddr 192.168.2.1 ip daddr 9.9.9.9 tcp dport 53"
    ];
  };

  hasDnsEgressRules =
    containerName:
    let
      script = dnsNftScriptFor containerName;
    in
    builtins.all (fragment: lib.hasInfix fragment script) dnsEgressFragments.${containerName};

  keaServiceFor =
    containerName: vlanName:
      config.containers.${containerName}.config.systemd.services."kea-dhcp4-${vlanName}" or { };

  keaGenServiceFor =
    containerName: vlanName:
      config.containers.${containerName}.config.systemd.services."gen-kea-${vlanName}" or { };

  execStartPostList =
    value:
    if builtins.isList value then
      value
    else if value == null then
      [ ]
    else
      [ value ];

  hasLegacyKeaLeasePaths =
    let
      hasContainer =
        containerName: vlanName:
        let
          keaService = keaServiceFor containerName vlanName;
          genService = keaGenServiceFor containerName vlanName;
          postHooks = execStartPostList (genService.serviceConfig.ExecStartPost or null);
        in
        (keaService.serviceConfig.StateDirectory or null) == "kea"
        && builtins.any
          (hook: lib.hasInfix "rewrite-kea-${vlanName}-lease-path" (toString hook))
          postHooks;
    in
    hasContainer "access-vlan2" "vlan2"
    && hasContainer "access-vlan3" "vlan3"
    && hasContainer "access-vlan7" "vlan7";

  hasVlan3SecretReservation =
    let
      postHooks = execStartPostList (
        (keaGenServiceFor "access-vlan3" "vlan3").serviceConfig.ExecStartPost or null
      );
    in
    config.sops.secrets ? s-nebula-container-mac
    && builtins.any
      (hook: lib.hasInfix "apply-s-router-prod-vlan3-kea-reservation" (toString hook))
      postHooks;

  coreNftables = config.containers.core.config.networking.nftables.ruleset;
  policyNftables = config.containers.policy.config.networking.nftables.ruleset;
  upstreamSelectorNftables =
    config.containers.upstream-selector.config.networking.nftables.ruleset;

  hasNebulaPublicIngressRules =
    builtins.all (fragment: lib.hasInfix fragment coreNftables) [
      ''iifname "ppp0" oifname "ens3" ct status dnat meta nfproto ipv4 ip daddr 192.168.3.10 meta l4proto udp udp dport 4242 accept comment "allow-wan-to-s-nebula-container"''
      ''iifname "ppp0" oifname "ens3" ct status dnat meta nfproto ipv4 ip daddr 192.168.3.10 meta l4proto tcp tcp dport 4242 accept comment "allow-wan-to-s-nebula-container"''
      ''iifname "ppp0" meta l4proto udp udp dport 4242 dnat to 192.168.3.10:4242 comment "allow-wan-to-s-nebula-container"''
      ''iifname "ppp0" meta l4proto tcp tcp dport 4242 dnat to 192.168.3.10:4242 comment "allow-wan-to-s-nebula-container"''
      ''oifname "ens3" ip daddr 192.168.3.10 meta l4proto udp udp dport 4242 snat to 10.19.0.3 comment "allow-wan-to-s-nebula-container-source-translation"''
      ''oifname "ens3" ip daddr 192.168.3.10 meta l4proto tcp tcp dport 4242 snat to 10.19.0.3 comment "allow-wan-to-s-nebula-container-source-translation"''
    ];

  hasStatefulVlan3Return =
    lib.hasInfix
      ''iifname "down-vlan3" oifname "down-vlan2" ct state established,related accept comment "allow-vlan2-to-vlan3"''
      policyNftables;

  hasIpv6CompatibilityGlue =
    builtins.hasAttr "dhcpcd-ipv6" (servicesFor "core")
    && builtins.hasAttr "s-router-prod-nebula-ipv6-firewall" (servicesFor "core")
    && builtins.hasAttr "s-router-prod-nebula-ipv6-firewall" (servicesFor "upstream-selector")
    && builtins.all (fragment: lib.hasInfix fragment coreNftables) [
      "s-router-prod-dhcpv6-replies"
      "s-router-prod-nebula6-forward-udp"
      "s-router-prod-nebula6-forward-tcp"
    ]
    && builtins.all (fragment: lib.hasInfix fragment upstreamSelectorNftables) [
      "s-router-prod-nebula4-forward-udp"
      "s-router-prod-nebula4-forward-tcp"
      "s-router-prod-nebula6-forward-udp"
      "s-router-prod-nebula6-forward-tcp"
    ];

  hasRoute =
    containerName: networkName: destination: gateway:
    builtins.any
      (route:
      (route.Destination or null) == destination
      && (route.Gateway or null) == gateway)
      (config.containers.${containerName}.config.systemd.network.networks.${networkName}.routes or [ ]);

  hasRendererNativeNebulaRoutes =
    hasRoute "core" "10-ens3" "192.168.3.10/32" "10.10.0.7"
    && hasRoute "upstream-selector" "10-policy-vlan3" "192.168.3.10/32" "10.10.0.16"
    && hasRoute "policy" "10-down-vlan3" "192.168.3.10/32" "10.10.0.10"
    && hasRoute "downstream-selector" "10-access-vlan3" "192.168.3.10/32" "10.10.0.2"
    && hasRoute "access-vlan3" "10-access-vlan3" "10.19.0.3/32" "10.10.0.3"
    && hasRoute "downstream-selector" "10-policy-vlan3" "10.19.0.3/32" "10.10.0.11"
    && hasRoute "policy" "10-upstream-vlan3" "10.19.0.3/32" "10.10.0.17"
    && hasRoute "upstream-selector" "10-core" "10.19.0.3/32" "10.10.0.6";

  hasNoVlan2Vlan3MainTableOverride =
    !(builtins.any
      (rule:
        (rule.Family or null) == "ipv4"
        && (rule.IncomingInterface or null) == "access-vlan3"
        && (rule.Priority or null) == 900
        && (rule.Table or null) == 254
        && (rule.To or null) == "192.168.1.0/24")
      (
        config.containers.downstream-selector.config.systemd.network.networks."10-access-vlan3".routingPolicyRules or [ ]
      ));

  hasRendererNativeVlan3Fallback =
    let
      downstreamNetworks = config.containers.downstream-selector.config.systemd.network.networks;
    in
    builtins.any
      (rule:
        (rule.Family or null) == "ipv4"
        && (rule.From or null) == "192.168.3.0/24"
        && (rule.IncomingInterface or null) == "access-vlan3"
        && (rule.Priority or null) == 11002
        && (rule.Table or null) == 254
        && (rule.SuppressPrefixLength or null) == 0)
      (downstreamNetworks."10-access-vlan3".routingPolicyRules or [ ])
    && builtins.any
      (route:
        (route.Destination or null) == "192.168.1.0/24"
        && (route.Gateway or null) == "10.10.0.0"
        && (route.Table or 254) == 254)
      (downstreamNetworks."10-access-vlan2".routes or [ ]);
in
{
  assertions = [
    {
      assertion = config.virtualisation.qemu.networkingOptions == expectedQemuNetworkingOptions;
      message = ''
        s-router-prod must keep the legacy VM NIC contract:
          eth0 -> vmbr4, MAC 52:54:00:12:34:56
          eth1 -> vmbr1, MAC 52:54:00:12:34:57
      '';
    }
    {
      assertion = config.networking.useNetworkd;
      message = ''
        s-router-prod must be interpreted as a rendered router host.

        The network-* renderer must enable systemd-networkd for this host when it
        emits host bridges and container hostBridge attachments. Do not add a
        local networking.useNetworkd workaround in s-router-prod/default.nix.
      '';
    }
    {
      assertion = config.systemd.network.enable;
      message = ''
        s-router-prod rendered host networking must be managed by systemd-networkd.

        This is required for the generated LAN/WAN/transit bridges to exist before
        the containers start.
      '';
    }
    {
      assertion = config.networking.useDHCP == false;
      message = ''
        s-router-prod must not use the legacy global DHCP generator.

        Host interface behavior must come from prod-network/s-router-prod/inventory.nix
        through the network-* render pipeline.
      '';
    }
    {
      assertion = builtins.elem "br-lan-trunk" netdevBridgeNames;
      message = ''
        s-router-prod must render the legacy LAN handoff bridge br-lan-trunk from inventory.
      '';
    }
    {
      assertion = builtins.elem "br-wan6" netdevBridgeNames;
      message = ''
        s-router-prod must render the WAN PPPoE lower bridge br-wan6 from inventory.
      '';
    }
    {
      assertion =
        builtins.elem "lan2" netdevBridgeNames
        && builtins.elem "lan3" netdevBridgeNames
        && builtins.elem "lan7" netdevBridgeNames;
      message = ''
        s-router-prod must render the client VLAN bridges lan2, lan3, and lan7 from inventory.
      '';
    }
    {
      assertion = hasExpectedContainers;
      message = ''
        s-router-prod must render exactly the production router roles from intent/inventory.

        The external ISP peer is a non-rendered model peer for PPPoE validation and
        must not become a local production container.
      '';
    }
    {
      assertion = builtins.elem "br-wan6" coreExtraVethBridges;
      message = ''
        s-router-prod core must attach its WAN side to the rendered br-wan6 handoff.
      '';
    }
    {
      assertion =
        config.sops.secrets ? pppoe-username
        && config.sops.secrets ? pppoe-password
        && config.sops.secrets ? s-router-prod-vlan2-reservations-json
        && config.sops.secrets ? s-nebula-container-mac;
      message = ''
        s-router-prod must keep PPPoE credentials, VLAN 2 reservations, and the
        s-nebula-container MAC wired as runtime secrets, not rendered model data.
      '';
    }
    {
      assertion =
        (config._module.args.sRouterProdModelSource.intentPath or null)
        == "${outPath}/prod-network/s-router-prod/intent.nix"
        && (config._module.args.sRouterProdModelSource.inventoryPath or null)
        == "${outPath}/prod-network/s-router-prod/inventory.nix";
      message = ''
        s-router-prod must consume the production intent.nix and inventory.nix directly.
      '';
    }
    {
      assertion =
        unboundForwardersFor "access-vlan2" == expectedDnsForwarders
        && unboundForwardersFor "access-vlan7" == expectedDnsForwarders;
      message = ''
        s-router-prod must render explicit prod-like recursive DNS forwarders for
        both client VLAN access containers.
      '';
    }
    {
      assertion = hasDnsEgressRules "access-vlan2" && hasDnsEgressRules "access-vlan7";
      message = ''
        s-router-prod must render DNS service egress from the local gateway source
        addresses, matching the FS-540-HDS-010-SDS-010-SMS-045 intent pattern.
      '';
    }
    {
      assertion = hasVlan3LocalDns && hasNoVlan3DnsUpstream;
      message = ''
        s-router-prod VLAN 3 must expose only local DMZ DNS data for
        s-nebula-container and must not render DNS upstream egress.
      '';
    }
    {
      assertion = hasVlan3SecretReservation;
      message = ''
        s-router-prod VLAN 3 must apply the s-nebula-container DHCP reservation
        from a runtime MAC secret instead of rendering the MAC into inventory or
        the Nix store.
      '';
    }
    {
      assertion = hasVlan2RuntimeLocalDns;
      message = ''
        s-router-prod must publish VLAN 2 runtime reservation hostnames through
        an Unbound lan. local-zone without leaking the private hostname source
        into inventory, flake eval output, or the Nix store.
      '';
    }
    {
      assertion = hasLegacyKeaLeasePaths;
      message = ''
        s-router-prod Kea lease databases must stay legacy-compatible at
        /var/lib/kea/<vlan>.leases with StateDirectory=kea.

        Kea's memfile path security only allows lease database files directly
        under /var/lib/kea; nested rendered paths under /var/lib/kea/dhcp4/...
        make kea-dhcp4 fail before serving DHCP.
      '';
    }
    {
      assertion = hasNebulaPublicIngressRules && hasRendererNativeNebulaRoutes;
      message = ''
        s-router-prod must receive scoped Nebula TCP/UDP 4242 DNAT, SNAT,
        forwarding, and dedicated VLAN 3 forward/return routes from the
        upstream CPM/renderer chain.
      '';
    }
    {
      assertion =
        hasRendererNativeIpv6Routes
        && hasNoExactTenantIpv6RouteCompatibility;
      message = ''
        s-router-prod must receive exact slot-derived tenant IPv6 routes from
        the renderer, without local s-router-prod-ipv6-routes compatibility
        services.
      '';
    }
    {
      assertion = hasIpv6CompatibilityGlue;
      message = ''
        s-router-prod must retain DHCPv6-PD acquisition and scoped Nebula IPv4/
        IPv6 ingress glue until those behaviors are modeled by the renderer.
      '';
    }
    {
      assertion =
        hasStatefulVlan3Return
        && hasNoVlan2Vlan3MainTableOverride
        && hasRendererNativeVlan3Fallback;
      message = ''
        s-router-prod VLAN 3 to VLAN 2 traffic must remain limited to
        established/related return traffic and use the renderer-native
        policy-routing fallback. Do not restore a local priority-900 override.
      '';
    }
  ];
}
