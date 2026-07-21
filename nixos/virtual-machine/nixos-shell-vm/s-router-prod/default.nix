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
    "VLAN 2 reservation names use a protected local DNS publisher because the native name-publication contract rejects the existing intentional multi-address names"
    "TEMPORARY: VLAN 2 host management DHCPv4 remains local because hostManagement is not yet materialized by the pinned network-* stack; the VLAN 2 to VLAN 3 policy and ICMP path are renderer-native"
    "DHCPv6-PD and protected Nebula IPv6 ingress remain local compatibility glue until the intent has an explicit native IPv6 public-ingress relation"
  ];

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    "${modelSource}/runtime-secrets.nix"
    ./ipv6.nix
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
