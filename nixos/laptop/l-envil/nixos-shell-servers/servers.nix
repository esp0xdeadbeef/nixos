{ ... }:
{
  imports = [
    (import ../../../server/nixos-shell-vm-inventory.nix {
      startOnBootInstances = [
        "s-router-cobalt"
        "s-nebula-cobalt"
        "s-tang"
        "s-ap-nighthawk"
        "s-ap-alfa"
      ];
      # Instances hosted elsewhere must not be built on l-envil: the
      # GPU-backed inference VM lives on s-tau, and the non-cobalt router VMs
      # (clab/nixos/neon/prod/legacy-prod lab and prod routers, VPN egress)
      # are owned by their respective hosts. l-envil only builds/starts the
      # cobalt site stack, so leave these VM images unbuilt.
      excludeInstances = [
        # GPU inference lives on s-tau.
        "s-llm-inference"
        # Lab / prod router VMs owned by other hosts.
        "s-router-clab"
        "s-router-nixos"
        "s-router-neon"
        "s-router-prod"
        "s-router-legacy-prod"
        "s-router-test-clients"
        "s-router-vpn-egress"
      ];
    })
  ];
}
