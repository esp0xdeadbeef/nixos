{ ... }:
{
  imports = [
    (import ../../neon/nixos-shell-vm-inventory.nix {
      # Preserve the legacy host's automatic-start authority during migration.
      startOnBootInstances = [
        "s-infra"
        "s-nebula"
        "s-agents"
        "s-router-clab"
        "s-router-nixos"
        "s-router-test-clients"
        "s-router-vpn-egress"
        "s-gameserver"
        "s-test"
      ];
    })
  ];
}
