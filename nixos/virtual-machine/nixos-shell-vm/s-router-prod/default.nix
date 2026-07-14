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
  sops.secrets.s-nebula-container-mac = { };

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./kea-legacy-lease-paths.nix
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
      nixosRendererInput = inputs.network-renderer-nixos-prod;
      system = "x86_64-linux";
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-prod/default.nix";
    })
  ];

  # Temporary until network-renderer-nixos materializes
  # publicIngressTupleAuthority as core-owned DNAT.
  containers.core.config.networking.nftables.ruleset = lib.mkAfter ''
    table ip s_router_prod_nebula_hotpatch {
      chain prerouting {
        type nat hook prerouting priority -101; policy accept;
        iifname "ppp0" udp dport 4242 counter dnat to 192.168.3.10:4242 comment "hotpatch-nebula-public-ingress-udp"
        iifname "ppp0" tcp dport 4242 counter dnat to 192.168.3.10:4242 comment "hotpatch-nebula-public-ingress-tcp"
      }
    }
  '';

  virtualisation.qemu.networkingOptions = lib.mkForce qemuNetworkingOptions;
}
