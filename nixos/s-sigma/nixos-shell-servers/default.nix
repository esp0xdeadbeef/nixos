{ pkgs,self, ... }:
{
  imports = [
    #./mk-nixos-shell-vm.nix # this is the generator, don't use it.
    ./servers.nix
  ];
}
