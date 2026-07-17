{ inputs
, lib
, outPath
, ...
}:
let
  hostName = "s-router-prod";
  system = "x86_64-linux";
  modelSource = "${outPath}/prod-network/s-router-prod";
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

  networking.hostName = lib.mkForce hostName;

  warnings = map (reason: "s-router-prod compatibility override: ${reason}") [
    "QEMU NICs override the generic VM definition to preserve the production vmbr4/vmbr1 handoff and both legacy MAC addresses"
    "Kea lease paths stay directly below /var/lib/kea because the pinned renderer emits nested memfile paths that Kea rejects"
    "VLAN 2 reservations use the existing aggregate private runtime secret, which must be migrated to the renderer protected reservation-set schema"
    "the VLAN 3 reservation uses an existing raw MAC secret, which must be migrated to the renderer protected reservation-set schema"
    "TEMPORARY: VLAN 2 host management DHCPv4, the priority-900 VLAN 2 to VLAN 3 policy selector, and its scoped post-policy ICMP handoff are local compatibility fixes; remove vlan2-management-override.nix once the pinned network-* stack materializes hostManagement and emits the symmetric service path end to end"
  ];

  sops.secrets =
    {
      pppoe-username = { };
      pppoe-password = { };
      s-nebula-container-mac = { };
      subnet-ipv6-vlan2 = {
        key = "subnet-ipv6";
        owner = "root";
        mode = "0400";
      };
      subnet-ipv6-vlan3 = {
        key = "subnet-ipv6";
        owner = "root";
        mode = "0400";
      };
      subnet-ipv6-vlan7 = {
        key = "subnet-ipv6";
        owner = "root";
        mode = "0400";
      };
    };

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./kea-legacy-lease-paths.nix
    ./ipv6.nix
    ./vlan2-kea-reservations-override.nix
    ./vlan2-management-override.nix
    ./vlan3-kea-reservations-override.nix
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
