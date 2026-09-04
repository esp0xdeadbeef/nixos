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
    })
  ];
}
