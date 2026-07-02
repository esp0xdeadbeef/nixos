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
in
{
  _module.args.sRouterProdProfile = {
    inherit modelSource;
    labSelector = null;
    productionSelector = hostName;
  };

  networking.hostName = lib.mkForce hostName;

  sops.secrets.pppoe-username = { };
  sops.secrets.pppoe-password = { };

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./vlan2-kea-reservations-override.nix

    (import ./renderers.nix {
      inherit
        inputs
        lib
        outPath
        hostName
        modelSource
        ;

      controlPlaneModelInput = inputs.network-control-plane-model-prod;
      nixosRendererInput = inputs.network-renderer-nixos-prod;
      system = "x86_64-linux";
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-prod/default.nix";
    })
  ];

  virtualisation.qemu.networkingOptions = lib.mkForce qemuNetworkingOptions;

  assertions = [
    {
      assertion = config.virtualisation.qemu.networkingOptions == qemuNetworkingOptions;
      message = ''
        s-router-prod must keep the legacy VM NIC contract:
          eth0 -> vmbr4, MAC 52:54:00:12:34:56
          eth1 -> vmbr1, MAC 52:54:00:12:34:57
      '';
    }
  ];
}
