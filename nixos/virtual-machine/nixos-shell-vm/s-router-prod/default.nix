{ inputs
, lib
, outPath
, ...
}:
let
  hostName = "s-router-prod";
  system = "x86_64-linux";
  modelSource = "${outPath}/prod-network/current";
  qemuNetworkingOptions = [
    "-nic none"
    "-nic bridge,br=vmbr4,mac=52:54:00:12:34:56,model=virtio-net-pci"
    "-nic bridge,br=vmbr1,mac=52:54:00:12:34:57,model=virtio-net-pci"
  ];
in
{
  _module.args.sRouterProdProfile = {
    inherit modelSource;
    labSelector = null;
    productionSelector = hostName;
  };

  warnings = map (reason: "s-router-prod compatibility override: ${reason}") [
    "QEMU NICs override the generic VM definition to preserve the production vmbr4/vmbr1 handoff and both legacy MAC addresses"
    "TEMPORARY NETWORK-RENDERER PROTECTED NAME-PUBLICATION OVERRIDE (vlan2-reservation-dns.nix): the native reservation name-publication contract rejects intentional multi-address hostnames; remove this file when network-* accepts that cardinality and renders protected runtime A/PTR data without exposing names through evaluation or the Nix store"
    "TEMPORARY NETWORK-RENDERER HOST MANAGEMENT OVERRIDE (vlan2-management-override.nix): VLAN 2 host management DHCPv4 remains local because hostManagement is not yet materialized by the pinned network-* stack; remove this file when network-* renders host DHCPv4 with UseDNS=false, while retaining the renderer-native VLAN 2 to VLAN 3 policy and ICMP path"
    "TEMPORARY NETWORK-RENDERER CORE DNS PATH OVERRIDE (dns-core-path-route-override.nix): the rendered policy tables copy equal-prefix core service routes across VLAN 2, VLAN 3, and VLAN 7, so DNS can leave through the wrong tenant lane and be dropped; remove this file when the network-* service-route closure keeps core DNS on each requester's relation-bound upstream lane"
    "TEMPORARY NETWORK-RENDERER IPv6 PATH-MTU OVERRIDE (vlan2-ipv6-path-mtu-override.nix): VLAN 2 advertises the core PPPoE MTU of 1492 because network-renderer-nixos does not yet propagate uplink path MTU into access router advertisements; remove this file when the rendered RA owns AdvLinkMTU, while retaining the renderer-native inet-family TCP MSS clamp"
    "TEMPORARY NETWORK-* IPv6 UPLINK/INGRESS OVERRIDE (ipv6.nix): DHCPv6-PD acquisition and protected Nebula IPv6 ingress remain local compatibility glue; remove the local services, runtime address set, and nftables rules when the intent/compiler/renderer natively model PD plus an explicit scoped IPv6 public-ingress relation"
  ];

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    "${modelSource}/runtime-secrets.nix"
    ./ipv6.nix
    ./dns-core-path-route-override.nix
    ./vlan2-ipv6-path-mtu-override.nix
    ./vlan2-reservation-dns.nix
    ./vlan2-management-override.nix
    ./legacy-parity-contract.nix

    (import ./renderers.nix {
      inherit
        inputs
        lib
        hostName
        modelSource
        ;

      controlPlaneModelInput = inputs.network-control-plane-model-prod;
      nixosRendererInput = inputs.network-renderer-nixos-prod;
      inherit system;
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-prod/default.nix";
    })
  ];

  virtualisation.qemu.networkingOptions = lib.mkForce qemuNetworkingOptions;
}
