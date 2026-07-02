{ config, lib, outPath, ... }:

let
  expectedQemuNetworkingOptions = [
    "-nic none"
    "-nic bridge,br=vmbr4,mac=52:54:00:12:34:56,model=virtio-net-pci"
    "-nic bridge,br=vmbr1,mac=52:54:00:12:34:57,model=virtio-net-pci"
  ];

  expectedContainers = [
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
      assertion = builtins.elem "lan2" netdevBridgeNames && builtins.elem "lan7" netdevBridgeNames;
      message = ''
        s-router-prod must render the legacy client VLAN bridges lan2 and lan7 from inventory.
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
        && config.sops.secrets ? s-router-prod-vlan2-reservations-json;
      message = ''
        s-router-prod must keep PPPoE credentials and VLAN 2 reservations wired as
        runtime secrets, not rendered model data.
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
  ];
}
