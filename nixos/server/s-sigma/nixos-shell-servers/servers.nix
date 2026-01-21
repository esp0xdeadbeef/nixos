{
  lib,
  pkgs,
  self,
  ...
}:
# for testing, use:
# nix run path:/home/deadbeef/github/nixos#nixosConfigurations.<vm-hostname>.config.system.build.nixos-shell

let
  mkVM = import ./mk-nixos-shell-vm.nix { inherit pkgs lib self; };
in
{
  config = lib.mkMerge [
    (mkVM "s-infra" (
      let
        repo = self.lib.vmSourceForPath "nixos/virtual-machine/nixos-shell-vms/s-infra";
      in
      {
        description = "Infra VM (nixos-shell)";
        repository = "path:${repo}";
      }
    ))

    (mkVM "s-router-edge" (
      let
        repo = self.lib.vmSourceForPath "nixos/virtual-machine/nixos-shell-vms/s-routers/2-edge";
      in
      {
        description = "s-router-edge VM (nixos-shell)";
        repository = "path:${repo}";
      }
    ))

    (mkVM "s-gameservers" (
      let
        repo = self.lib.vmSourceForPath "nixos/virtual-machine/nixos-shell-vms/s-gameservers";
      in
      {
        description = "Gameserver VM (nixos-shell)";
        repository = "path:${repo}";
      }
    ))

    (mkVM "s-router-vpn-egress" (
      let
        repo = self.lib.vmSourceForPath "nixos/virtual-machine/nixos-shell-vms/s-routers/z-vpn-egress";
      in
      {
        description = "VPN-egress VM (nixos-shell)";
        repository = "path:${repo}";
      }
    ))

    (mkVM "s-test" (
      let
        repo = self.lib.vmSourceForPath "nixos/virtual-machine/nixos-shell-vms/s-test";
      in
      {
        description = "s-test (nixos-shell)";
        repository = "path:${repo}";
        ephemeralRoot = true;
      }
    ))
  ];
}
