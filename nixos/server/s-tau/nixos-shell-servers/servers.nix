{ ... }:
{
  imports = [
    (import ../../nixos-shell-vm-inventory.nix {
      startOnBootInstances = [
        "s-llm-inference"
        "s-test"
      ];
    })
  ];
}
