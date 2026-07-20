{ ... }:
{
  imports = [
    (import ../../nixos-shell-vm-inventory.nix {
      startOnBootInstances = [ "s-test" ];
    })
  ];
}
