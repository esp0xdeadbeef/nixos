{ inputs, ... }:
{
  imports = [
    inputs.nixos-shell-vm-manager.nixosModules.default
  ];
}
