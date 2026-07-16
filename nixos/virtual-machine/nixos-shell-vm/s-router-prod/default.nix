{ config
, inputs
, lib
, outPath
, ...
}:
let
  hostName = "s-router-prod";
  modelSource = "${outPath}/prod-network/s-router-prod";
  qemuNetworkingOptions = [
    "-nic none"
    "-nic bridge,br=vmbr4,mac=52:54:00:12:34:56,model=virtio-net-pci"
    "-nic bridge,br=vmbr1,mac=52:54:00:12:34:57,model=virtio-net-pci"
  ];
  nebulaPublicIngressHotpatch = import ./nebula-public-ingress-hotpatch.nix {
    inherit lib;
  };
in
{
  _module.args.sRouterProdProfile = {
    inherit modelSource;
    labSelector = null;
    productionSelector = hostName;
  };

  networking.hostName = hostName;

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
    nebulaPublicIngressHotpatch.nixosModule
    ./ipv6.nix
    ./vlan2-vlan3-stateful-return-hotpatch.nix
    ./vlan2-kea-reservations-override.nix
    ./vlan3-kea-reservations-override.nix
    ./legacy-parity-contract.nix

    (import ./renderers.nix {
      inherit
        inputs
        lib
        outPath
        hostName
        modelSource
        ;

      controlPlaneModelInput = inputs.network-control-plane-model-prod;
      controlPlaneTransform = nebulaPublicIngressHotpatch.patchControlPlane;
      nixosRendererInput = inputs.network-renderer-nixos-prod;
      system = "x86_64-linux";
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-prod/default.nix";
    })
  ];

  virtualisation.qemu.networkingOptions = lib.mkForce qemuNetworkingOptions;
}
