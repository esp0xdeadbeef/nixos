{ inputs
, lib
, relativeRepo
, ...
}:
let
  hostName = "s-router-prod-testing";
  modelSource = relativeRepo.sourcePath "prod-network/current";
in
{
  _module.args.sRouterProdProfile = {
    inherit modelSource;
    labSelector = null;
    productionSelector = "s-router-prod";
  };

  networking.hostName = lib.mkForce hostName;

  warnings = map (reason: "s-router-prod-testing compatibility override: ${reason}") [
    "TEMPORARY NETWORK-RENDERER PROTECTED NAME-PUBLICATION OVERRIDE (vlan2-reservation-dns.nix): the native reservation name-publication contract rejects intentional multi-address hostnames; remove this file when network-* accepts that cardinality and renders protected runtime A/PTR data without exposing names through evaluation or the Nix store"
    "TEMPORARY NETWORK-* VLAN 3 DNS AUTHORITY OVERRIDE (vlan3-dns-authority-override.nix plus vlan2-reservation-dns.nix filtering): VLAN 2 must query VLAN 3 Unbound for VLAN 3-owned names; remove both pieces when network-* supports multiple directional, relation-bound local namespace authorities"
    "TEMPORARY NETWORK-RENDERER HOST MANAGEMENT OVERRIDE (vlan2-management-override.nix): VLAN 2 host management DHCPv4 remains local; remove this file when network-* renders host DHCPv4 with UseDNS=false"
    "TEMPORARY NETWORK-RENDERER CORE DNS PATH OVERRIDE (dns-core-path-route-override.nix): the rendered policy tables copy equal-prefix core service routes across VLAN lanes; remove this file when the network-* service-route closure keeps core DNS on each requester's relation-bound upstream lane"
    "TEMPORARY NETWORK-* NEBULA INGRESS PATH OVERRIDE (nebula-ingress-path-route-override.nix): the rendered policy tables copy the core-owned Nebula SNAT return route across tenant lanes; remove this file when network-* emits symmetric relation-bound forward and return policy routes for public ingress"
    "TEMPORARY NETWORK-RENDERER IPv6 PATH-MTU OVERRIDE (vlan2-ipv6-path-mtu-override.nix): VLAN 2 advertises the core PPPoE MTU of 1492; remove this file when the rendered RA owns AdvLinkMTU"
    "TEMPORARY NETWORK-* IPv6 UPLINK/INGRESS OVERRIDE (ipv6.nix): DHCPv6-PD acquisition and protected Nebula IPv6 ingress remain local compatibility glue; remove these when the intent/compiler/renderer natively model PD plus an explicit scoped IPv6 public-ingress relation"
  ];

  imports = [
    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config-routers-without-network")
    "${modelSource}/runtime-secrets.nix"
    ../s-router-prod/ipv6.nix
    ../s-router-prod/dns-core-path-route-override.nix
    ../s-router-prod/forwarding-invariants.nix
    ../s-router-prod/nebula-ingress-path-route-override.nix
    ../s-router-prod/vlan2-ipv6-path-mtu-override.nix
    ../s-router-prod/vlan2-reservation-dns.nix
    ../s-router-prod/vlan3-dns-authority-override.nix
    ../s-router-prod/vlan2-management-override.nix
    (import ../s-router-prod/renderers.nix {
      inherit
        inputs
        lib
        hostName
        modelSource
        ;

      controlPlaneModelInput = inputs.network-control-plane-model-prod;
      networkRealizationModelInput = inputs.network-realization-model-prod;
      nixosRendererInput = inputs.network-renderer-nixos-prod;
      system = "x86_64-linux";
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-prod-testing/default.nix";
    })

    ../s-router-prod/legacy-parity-contract.nix
  ];

  system.stateVersion = lib.mkForce "26.05";
}
