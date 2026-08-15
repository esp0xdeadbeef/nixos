{ ... }:
{
  imports = [
    (import ../../neon/nixos-shell-vm-inventory.nix {
      startOnBootInstances = [
        "s-llm-inference"
        "s-mail-classifier"
        "s-test"
      ];
    })
  ];
}
